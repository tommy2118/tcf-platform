# frozen_string_literal: true

require 'open3'

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
      port_map = {
        'tcf-gateway' => 3000,
        'tcf-personas' => 3001,
        'tcf-workflows' => 3002,
        'tcf-projects' => 3003,
        'tcf-context' => 3004,
        'tcf-tokens' => 3005
      }
      port_map[service_name] || nil
    end
  end
end