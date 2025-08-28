# frozen_string_literal: true

require_relative '../docker_manager'
require_relative '../service_registry'

module TcfPlatform
  class CLI < Thor
    # Docker orchestration commands for TCF Platform services
    module OrchestrationCommands
      def self.included(base)
        base.class_eval do
          desc 'up [SERVICE]', 'Start TCF Platform services'
          def up(service = nil)
            docker_manager = TcfPlatform::DockerManager.new

            if service
              service_name = normalize_service_name(service)
              puts "Starting #{service_name}..."
              services_started = docker_manager.start_services([service_name])
              puts "✅ Started services: #{services_started.join(', ')}"
            else
              puts 'Starting TCF Platform services...'
              services_started = docker_manager.start_services
              puts "✅ Started #{services_started.length} services: #{services_started.join(', ')}"
            end
          end

          desc 'down', 'Stop TCF Platform services'
          def down
            puts 'Stopping TCF Platform services...'
            docker_manager = TcfPlatform::DockerManager.new
            docker_manager.stop_services
            puts '✅ All services stopped successfully'
          end

          desc 'restart [SERVICE]', 'Restart TCF Platform services'
          def restart(service = nil)
            docker_manager = TcfPlatform::DockerManager.new

            if service
              service_name = normalize_service_name(service)
              puts "Restarting #{service_name}..."
              docker_manager.restart_services([service_name])
              puts "✅ Restarted #{service_name}"
            else
              puts 'Restarting TCF Platform services...'
              docker_manager.restart_services
              puts '✅ All services restarted successfully'
            end
          end

          private

          def normalize_service_name(service)
            # Allow shorthand service names
            case service.downcase
            when 'gateway'
              'tcf-gateway'
            when 'personas'
              'tcf-personas'
            when 'workflows'
              'tcf-workflows'
            when 'projects'
              'tcf-projects'
            when 'context'
              'tcf-context'
            when 'tokens'
              'tcf-tokens'
            else
              service
            end
          end
        end
      end
    end
  end
end
