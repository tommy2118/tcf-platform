# frozen_string_literal: true

require 'thor'
require_relative '../tcf_platform'
require_relative '../docker_manager'
require_relative '../service_registry'

module TcfPlatform
  class CLI < Thor
    class_option :verbose, type: :boolean, default: false, desc: 'Enable verbose output'

    desc 'version', 'Display the version'
    def version
      puts "TCF Platform version #{TcfPlatform.version}"
    end

    desc 'help [COMMAND]', 'Display help information'
    def help(command = nil)
      if command
        super
      else
        puts 'tcf-platform commands:'
        puts '  tcf-platform help [COMMAND]    # Display help information'
        puts '  tcf-platform version           # Display the version'
        puts '  tcf-platform server            # Start the TCF Platform server'
        puts '  tcf-platform status            # Display application status'
        puts '  tcf-platform up [SERVICE]      # Start TCF Platform services'
        puts '  tcf-platform down              # Stop TCF Platform services'
        puts '  tcf-platform restart [SERVICE] # Restart TCF Platform services'
        puts ''
        puts 'Options:'
        puts '  [--verbose], [--no-verbose]  # Enable verbose output'
      end
    end

    desc 'server', 'Start the TCF Platform server'
    option :port, type: :numeric, default: 3000, desc: 'Port to run server on'
    option :environment, type: :string, default: 'development', desc: 'Environment to run in'
    option :host, type: :string, default: '0.0.0.0', desc: 'Host to bind to'
    def server
      port = options[:port] || 3000
      env = options[:environment] || 'development'
      host = options[:host] || '0.0.0.0'

      puts 'Starting TCF Platform server...'
      puts "  Port: #{port}"
      puts "  Host: #{host}"
      puts "  Environment: #{env}" if env != 'development'
      puts ''

      ENV['RACK_ENV'] = env
      ENV['PORT'] = port.to_s
      ENV['BIND_HOST'] = host

      command = build_server_command(port, host)
      puts "Executing: #{command}" if options[:verbose]

      exec(command)
    end

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

    def build_server_command(port, host)
      config_ru = File.join(TcfPlatform.root, 'config.ru')
      "rackup #{config_ru} -p #{port} -o #{host}"
    end

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
      puts format('%-15s %-12s %-8s %-6s', 'Service', 'Status', 'Health', 'Port')
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
