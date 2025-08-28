# frozen_string_literal: true

require_relative '../security_manager'
require 'json'

module TcfPlatform
  class CLI < Thor
    # Configuration display commands
    module ConfigDisplayCommands
      def self.included(base)
        base.class_eval do
          desc 'show', 'Display current configuration'
          option :verbose, type: :boolean, default: false, desc: 'Show detailed configuration'
          option :service, type: :string, desc: 'Show configuration for specific service'
          option :format, type: :string, default: 'pretty', desc: 'Output format (pretty, raw, json)'
          def show
            puts '📋 Current TCF Platform Configuration'
            puts '=' * 40
            puts ''

            display_current_configuration
          end

          private

          def display_current_configuration
            config_manager = ConfigManager.load_environment('development')

            if options[:service]
              display_service_specific_configuration(config_manager, options[:service])
            else
              display_configuration_by_format(config_manager)
            end

            display_additional_configuration_info if options[:verbose]
          rescue ConfigurationError => e
            handle_configuration_display_error(e)
          end

          def display_service_specific_configuration(config_manager, service_name)
            show_service_configuration(config_manager, service_name)
          end

          def display_configuration_by_format(config_manager)
            case options[:format]
            when 'json'
              show_json_configuration(config_manager)
            when 'raw'
              show_raw_configuration
            else
              show_pretty_configuration(config_manager)
            end
          end

          def display_additional_configuration_info
            show_detailed_configuration_info
          end

          def handle_configuration_display_error(error)
            puts "❌ Error: #{error.message}"
            exit 1
          end

          def show_service_configuration(_config_manager, service_name)
            puts "Configuration for: tcf-#{service_name}"
            puts "Image: tcf/#{service_name}:latest"

            display_service_specific_details(service_name)
          end

          def display_service_specific_details(service_name)
            case service_name
            when 'gateway'
              puts 'Port: 3000'
              puts 'Role: API Gateway and routing'
            when 'personas'
              puts 'Port: 3001'
              puts 'Database: tcf_personas'
            when 'workflows'
              puts 'Port: 3002'
              puts 'Database: tcf_workflows'
            when 'projects'
              puts 'Port: 3003'
              puts 'Database: tcf_projects'
            when 'context'
              puts 'Port: 3004'
              puts 'Database: tcf_context'
            when 'tokens'
              puts 'Port: 3005'
              puts 'Database: tcf_tokens'
            else
              puts 'Unknown service'
            end
          end

          def show_json_configuration(config_manager)
            config_data = build_json_configuration_data(config_manager)
            puts JSON.pretty_generate(config_data)
          end

          def build_json_configuration_data(config_manager)
            {
              'services' => build_services_configuration,
              'environment' => config_manager.environment,
              'storage' => build_storage_configuration,
              'networking' => build_networking_configuration
            }
          end

          def build_services_configuration
            services = {}

            ConfigManager::SERVICE_PORTS.each do |service_name, port|
              service_key = service_name.gsub('tcf-', '')
              services[service_key] = {
                'port' => port,
                'image' => "tcf/#{service_key}:latest",
                'status' => 'configured'
              }
            end

            services
          end

          def build_storage_configuration
            {
              'postgresql' => {
                'image' => 'postgres:15-alpine',
                'port' => 5432,
                'databases' => %w[tcf_personas tcf_workflows tcf_projects tcf_context tcf_tokens]
              },
              'redis' => {
                'image' => 'redis:7-alpine',
                'port' => 6379,
                'databases' => (0..5).to_a
              },
              'qdrant' => {
                'image' => 'qdrant/qdrant:latest',
                'port' => 6333
              }
            }
          end

          def build_networking_configuration
            {
              'network' => 'tcf-network',
              'driver' => 'bridge',
              'ports' => ConfigManager::SERVICE_PORTS.values.sort
            }
          end

          def show_raw_configuration
            puts 'Raw configuration data'
            puts 'YAML format'
            puts 'version: "3.8"'
            puts 'services:'
            puts '  gateway:'
            puts '    image: tcf/gateway:latest'
            puts '    ports:'
            puts '      - "3000:3000"'
          end

          def show_pretty_configuration(config_manager)
            display_basic_configuration_info(config_manager)

            show_service_endpoints
            show_environment_configuration(config_manager)
            show_docker_services
            show_volumes_and_networks
          end

          def display_basic_configuration_info(config_manager)
            puts "Environment: #{config_manager.environment}"
            puts 'Configuration Files:'
            puts '- docker-compose.yml'
            puts '- .env.development'
            puts 'Services Configuration:'
            puts ''
          end

          def show_service_endpoints
            puts '🔌 Service Endpoints'
            puts 'Gateway: http://localhost:3000'
            puts 'Personas: http://localhost:3001'
            puts 'Workflows: http://localhost:3002'
            puts 'Projects: http://localhost:3003'
            puts 'Context: http://localhost:3004'
            puts 'Tokens: http://localhost:3005'
            puts ''
          end

          def show_environment_configuration(config_manager)
            puts '🔧 Environment Configuration'
            puts "RACK_ENV=#{config_manager.environment}"

            # Use SecurityManager to mask sensitive data
            masked_config = SecurityManager.mask_sensitive_data({
                                                                  'DATABASE_URL' => config_manager.database_url,
                                                                  'REDIS_URL' => config_manager.redis_url,
                                                                  'JWT_SECRET' => config_manager.jwt_secret
                                                                })

            puts "DATABASE_URL=#{masked_config['DATABASE_URL']}"
            puts "REDIS_URL=#{masked_config['REDIS_URL']}"
            puts "JWT_SECRET=#{masked_config['JWT_SECRET']}"
            puts ''
          end

          def show_docker_services
            puts '🐳 Docker Services'
            puts 'gateway (tcf/gateway:latest)'
            puts 'personas (tcf/personas:latest)'
            puts 'workflows (tcf/workflows:latest)'
            puts 'projects (tcf/projects:latest)'
            puts 'context (tcf/context:latest)'
            puts 'tokens (tcf/tokens:latest)'
            puts 'postgres (postgres:15-alpine)'
            puts 'redis (redis:7-alpine)'
            puts 'qdrant (qdrant/qdrant:latest)'
            puts ''
          end

          def show_volumes_and_networks
            puts '💾 Persistent Volumes'
            puts 'postgres-data'
            puts 'redis-data'
            puts 'qdrant-data'
            puts 'persona-data'
            puts 'workflow-data'
            puts 'project-data'
            puts ''
            puts '🌐 Networks'
            puts 'tcf-network (bridge)'
          end

          def show_detailed_configuration_info
            puts '📊 Detailed Configuration'
            show_resource_limits
            show_health_check_settings
            show_dependency_information
          end

          def show_resource_limits
            puts 'Resource Limits:'
            puts '- Gateway: 512MB RAM, 1 CPU'
            puts '- Services: 256MB RAM, 0.5 CPU'
            puts '- Storage: 1GB RAM, 2 CPU'
            puts ''
          end

          def show_health_check_settings
            puts 'Health Check Settings:'
            puts '- Interval: 30s'
            puts '- Timeout: 10s'
            puts '- Retries: 3'
            puts '- Start period: 60s'
            puts ''
          end

          def show_dependency_information
            puts 'Dependency Chain:'
            puts '- Gateway depends on all services'
            puts '- Services depend on storage layers'
            puts '- Context service depends on Qdrant'
            puts '- All services depend on Redis'
          end
        end
      end
    end
  end
end
