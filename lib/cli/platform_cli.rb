# frozen_string_literal: true

require 'thor'
require_relative '../tcf_platform'
require_relative 'orchestration_commands'
require_relative 'status_commands'
require_relative 'config_commands'
require_relative 'repository_commands'
require_relative 'dev_commands'
require_relative 'backup_commands'
require_relative 'monitoring_commands'
require_relative 'production_commands'

module TcfPlatform
  # Main CLI class for TCF Platform management
  class CLI < Thor
    include OrchestrationCommands
    include StatusCommands
    include ConfigCommands
    include RepositoryCommands
    include DevCommands
    include BackupCommands
    include MonitoringCommands
    include ProductionCommands

    class_option :verbose, type: :boolean, default: false, desc: 'Enable verbose output'

    # Development Commands
    desc 'dev-setup', 'Set up complete TCF development environment'
    option :verbose, type: :boolean, default: false, desc: 'Enable verbose output'
    option :force, type: :boolean, default: false, desc: 'Force setup even if environment appears ready'
    def dev_setup
      setup_development_environment
    end

    desc 'dev-test [SERVICE]', 'Run tests across TCF services'
    option :parallel, type: :boolean, default: false, desc: 'Run tests in parallel'
    option :integration, type: :boolean, default: false, desc: 'Run integration tests'
    option :verbose, type: :boolean, default: false, desc: 'Enable verbose output'
    def dev_test(service = nil)
      run_development_tests(service)
    end

    desc 'dev-migrate [SERVICE]', 'Manage database migrations across TCF services'
    option :rollback, type: :numeric, desc: 'Rollback N migration steps'
    option :status, type: :boolean, default: false, desc: 'Show migration status'
    option :verbose, type: :boolean, default: false, desc: 'Enable verbose output'
    def dev_migrate(service = nil)
      manage_database_migrations(service)
    end

    desc 'dev-doctor', 'Comprehensive TCF development environment diagnostics'
    option :verbose, type: :boolean, default: false, desc: 'Enable verbose diagnostics'
    option :quick, type: :boolean, default: false, desc: 'Quick health check only'
    def dev_doctor
      run_environment_diagnostics
    end

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
        puts 'Configuration Commands:'
        puts '  tcf-platform config            # Display configuration help'
        puts '  tcf-platform generate <env>    # Generate configuration files'
        puts '  tcf-platform validate          # Validate configuration'
        puts '  tcf-platform show              # Show current configuration'
        puts '  tcf-platform migrate           # Migrate configuration'
        puts '  tcf-platform reset             # Reset configuration'
        puts ''
        puts 'Repository & Build Commands:'
        puts '  tcf-platform repos status      # Show repository status'
        puts '  tcf-platform repos clone       # Clone missing repositories'
        puts '  tcf-platform repos update      # Update existing repositories'
        puts '  tcf-platform build [SERVICE]   # Build services'
        puts '  tcf-platform build-status      # Show build status'
        puts ''
        puts 'Development Commands:'
        puts '  tcf-platform dev-setup          # Set up development environment'
        puts '  tcf-platform dev-test [SERVICE] # Run tests (--parallel, --integration)'
        puts '  tcf-platform dev-migrate [SVC]  # Database migrations (--status, --rollback N)'
        puts '  tcf-platform dev-doctor         # Environment diagnostics (--quick, --verbose)'
        puts ''
        puts 'Backup & Recovery Commands:'
        puts '  tcf-platform backup-create ID   # Create backup (--incremental)'
        puts '  tcf-platform backup-list        # List backups (--from DATE, --to DATE)'
        puts '  tcf-platform backup-restore ID  # Restore backup (--components LIST, --force)'
        puts '  tcf-platform backup-validate ID # Validate backup integrity'
        puts '  tcf-platform backup-status      # Show backup system status'
        puts ''
        puts 'Monitoring & Metrics Commands:'
        puts '  tcf-platform metrics-show [SVC] # Show current metrics (--format json)'
        puts '  tcf-platform metrics-export     # Export Prometheus metrics (--output FILE)'
        puts '  tcf-platform metrics-query S M  # Query historical data (--start-time, --end-time)'
        puts '  tcf-platform monitor-start      # Start monitoring system (--background)'
        puts '  tcf-platform monitor-stop       # Stop monitoring system'
        puts '  tcf-platform monitor-status     # Show monitoring status (--verbose)'
        puts '  tcf-platform monitor-dashboard  # Start web dashboard (--port 3001)'
        puts '  tcf-platform monitor-cleanup    # Clean expired metrics (--dry-run)'
        puts ''
        puts 'Production Commands:'
        puts '  tcf-platform prod deploy VERSION   # Deploy to production (--strategy blue_green)'
        puts '  tcf-platform prod rollback [VER]   # Rollback deployment (--to-version, --service)'
        puts '  tcf-platform prod status           # Production status (--services, --health, --metrics)'
        puts '  tcf-platform prod audit            # Security audit (--comprehensive, --output FILE)'
        puts '  tcf-platform prod validate         # Validate readiness (--version, --security-scan)'
        puts '  tcf-platform prod monitor          # Manage monitoring (--action start/stop/status)'
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

    def platform_config
      @platform_config ||= TcfPlatform::ConfigManager.load_environment
    end

    def docker_manager
      @docker_manager ||= TcfPlatform::DockerManager.new
    end
  end
end
