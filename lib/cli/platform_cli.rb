# frozen_string_literal: true

require 'thor'
require_relative '../tcf_platform'
require_relative 'orchestration_commands'
require_relative 'status_commands'

module TcfPlatform
  # Main CLI class for TCF Platform management
  class CLI < Thor
    include OrchestrationCommands
    include StatusCommands

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

    private

    def build_server_command(port, host)
      config_ru = File.join(TcfPlatform.root, 'config.ru')
      "rackup #{config_ru} -p #{port} -o #{host}"
    end
  end
end
