# frozen_string_literal: true

require 'thor'
require_relative '../tcf_platform'

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
  end
end
