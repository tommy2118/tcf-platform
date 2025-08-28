# frozen_string_literal: true

module TcfPlatform
  # Registry for TCF service definitions and dependencies
  class ServiceRegistry
    SERVICE_DEPENDENCIES = {
      'tcf-gateway' => ['redis'],
      'tcf-personas' => %w[postgres redis],
      'tcf-workflows' => %w[postgres redis],
      'tcf-projects' => %w[postgres redis],
      'tcf-context' => %w[postgres redis],
      'tcf-tokens' => %w[postgres redis],
      'postgres' => [],
      'redis' => []
    }.freeze

    SERVICE_PORTS = {
      'tcf-gateway' => 3000,
      'tcf-personas' => 3001,
      'tcf-workflows' => 3002,
      'tcf-projects' => 3003,
      'tcf-context' => 3004,
      'tcf-tokens' => 3005,
      'postgres' => 5432,
      'redis' => 6379
    }.freeze

    def self.tcf_services
      SERVICE_DEPENDENCIES.keys.select { |service| service.start_with?('tcf-') }
    end

    def self.all_services
      SERVICE_DEPENDENCIES.keys
    end

    def self.dependencies_for(service)
      SERVICE_DEPENDENCIES[service] || []
    end

    def self.port_for(service)
      SERVICE_PORTS[service]
    end

    def self.resolve_dependencies(services)
      resolved = []
      services.each do |service|
        dependencies_for(service).each do |dep|
          resolved << dep unless resolved.include?(dep)
        end
        resolved << service unless resolved.include?(service)
      end
      resolved
    end
  end
end
