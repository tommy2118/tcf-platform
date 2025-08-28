# frozen_string_literal: true

require_relative '../docker_manager'

module TcfPlatform
  class CLI < Thor
    # Status and health check commands
    module StatusCommands
      def self.included(base)
        base.class_eval do
          desc 'status', 'Display application status'
          def status
            puts 'TCF Platform Status'
            puts '=' * 20
            puts "Version: #{TcfPlatform.version}"
            puts "Environment: #{TcfPlatform.env}"
            puts "Root: #{TcfPlatform.root}"
            puts ''

            # Check if server is running
            check_server_status
            puts ''

            # Check Docker services
            check_docker_services
          end

          private

          def check_server_status
            require 'net/http'
            require 'uri'

            port = ENV.fetch('PORT', 3000)
            uri = URI("http://localhost:#{port}/health")

            begin
              response = Net::HTTP.get_response(uri)
              if response.code == '200'
                puts "Server Status: Running on port #{port}"
              else
                puts "Server Status: Not responding properly (HTTP #{response.code})"
              end
            rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
              puts "Server Status: Not running on port #{port}"
            rescue StandardError => e
              puts "Server Status: Unknown (#{e.message})"
            end
          end

          def check_docker_services
            docker_manager = TcfPlatform::DockerManager.new

            puts 'Service Status'
            puts '-' * 50
            puts 'Service         Status       Health   Port  '
            puts '-' * 50

            service_status = docker_manager.service_status
            service_status.each do |service_name, info|
              status_icon = info[:status] == 'running' ? '🟢' : '🔴'
              health_icon = case info[:health]
                            when 'healthy' then '✅'
                            when 'unhealthy' then '❌'
                            else '❓'
                            end

              puts format('%-15s %-12s %-8s %-6s',
                          service_name,
                          "#{status_icon} #{info[:status]}",
                          "#{health_icon} #{info[:health]}",
                          info[:port])
            end
          end
        end
      end
    end
  end
end
