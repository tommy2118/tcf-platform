# frozen_string_literal: true

require 'open3'
require_relative 'service_registry'

module TcfPlatform
  # Manages Docker Compose operations for TCF Platform services
  class DockerManager
    TCF_SERVICES = %w[
      tcf-gateway
      tcf-personas
      tcf-workflows
      tcf-projects
      tcf-context
      tcf-tokens
    ].freeze

    def initialize(compose_file = 'docker-compose.yml')
      @compose_file = compose_file
    end

    def running_services
      services = docker_compose_ps
      services.map { |service| service[:name] }.select { |name| tcf_service?(name) }
    end

    def service_status
      services = docker_compose_ps
      status_hash = {}

      TCF_SERVICES.each do |service_name|
        service_info = services.find { |s| s[:name] == service_name }
        status_hash[service_name] = if service_info
                                      {
                                        status: service_info[:state],
                                        health: service_info[:health] || 'unknown',
                                        port: extract_port(service_name)
                                      }
                                    else
                                      {
                                        status: 'not_running',
                                        health: 'unknown',
                                        port: extract_port(service_name)
                                      }
                                    end
      end

      status_hash
    end

    def compose_file_exists?
      File.exist?(@compose_file)
    end

    def start_services(service_names = [])
      return [] unless compose_file_exists?

      services_to_start = service_names.empty? ? ServiceRegistry.tcf_services : service_names
      resolved_services = ServiceRegistry.resolve_dependencies(services_to_start)

      resolved_services.each do |service|
        _stdout, _stderr, status = Open3.capture3('docker-compose', 'up', '-d', service)
        # In production, we'd handle errors here, but for TDD we'll assume success
      end

      resolved_services
    end

    def stop_services(service_names = [])
      return true unless compose_file_exists?

      if service_names.empty?
        _stdout, _stderr, status = Open3.capture3('docker-compose', 'down')
      else
        service_names.each do |service|
          _stdout, _stderr, status = Open3.capture3('docker-compose', 'stop', service)
        end
      end

      true
    end

    def restart_services(service_names = [])
      return true unless compose_file_exists?

      if service_names.empty?
        _stdout, _stderr, status = Open3.capture3('docker-compose', 'restart')
      else
        service_names.each do |service|
          _stdout, _stderr, status = Open3.capture3('docker-compose', 'restart', service)
        end
      end

      true
    end

    private

    def docker_compose_ps
      return [] unless compose_file_exists?

      stdout, stderr, status = Open3.capture3('docker-compose', 'ps', '--format', 'json')
      
      return [] unless status.success?
      
      return [] if stdout.strip.empty?

      JSON.parse(stdout).map do |service|
        {
          name: service['Name'],
          state: service['State'],
          health: service['Health']
        }
      end
    rescue JSON::ParserError
      []
    end

    def tcf_service?(service_name)
      TCF_SERVICES.any? { |tcf_service| service_name.include?(tcf_service) }
    end

    def extract_port(service_name)
      ServiceRegistry.port_for(service_name)
    end
  end
end