# frozen_string_literal: true

require_relative '../dev_environment'
require_relative '../test_coordinator'
require_relative '../migration_manager'

module TcfPlatform
  # Development Commands Module for CLI
  # Provides comprehensive development workflow commands for TCF Platform
  module DevCommands
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def define_dev_commands
        desc 'dev-setup', 'Set up complete TCF development environment'
        option :verbose, type: :boolean, default: false, desc: 'Enable verbose output'
        option :force, type: :boolean, default: false, desc: 'Force setup even if environment appears ready'
        define_method :dev_setup do
          setup_development_environment
        end

        desc 'dev-test [SERVICE]', 'Run tests across TCF services'
        option :parallel, type: :boolean, default: false, desc: 'Run tests in parallel'
        option :integration, type: :boolean, default: false, desc: 'Run integration tests'
        option :verbose, type: :boolean, default: false, desc: 'Enable verbose output'
        define_method :dev_test do |service = nil|
          run_development_tests(service)
        end

        desc 'dev-migrate [SERVICE]', 'Manage database migrations across TCF services'
        option :rollback, type: :numeric, desc: 'Rollback N migration steps'
        option :status, type: :boolean, default: false, desc: 'Show migration status'
        option :verbose, type: :boolean, default: false, desc: 'Enable verbose output'
        define_method :dev_migrate do |service = nil|
          manage_database_migrations(service)
        end

        desc 'dev-doctor', 'Comprehensive TCF development environment diagnostics'
        option :verbose, type: :boolean, default: false, desc: 'Enable verbose diagnostics'
        option :quick, type: :boolean, default: false, desc: 'Quick health check only'
        define_method :dev_doctor do
          run_environment_diagnostics
        end
      end
    end

    private

    def setup_development_environment
      puts '🚀 Setting up TCF development environment...'
      puts ''

      begin
        dev_environment = TcfPlatform::DevEnvironment.new

        if options[:verbose]
          puts 'Verbose mode enabled - detailed output will be shown'
          puts "Force mode: #{options[:force] ? 'enabled' : 'disabled'}"
          puts ''
        end

        puts '📋 Prerequisites Check'
        puts '=' * 50

        # Run setup
        result = dev_environment.setup

        if result[:status] == 'success'
          puts '✅ Development environment setup completed successfully!'
          puts ''
          puts '📊 Setup Summary:'
          puts "  Prerequisites validated: #{result[:prerequisites_validated] ? '✅' : '❌'}"
          puts "  Steps completed: #{result[:steps_completed].size}"

          result[:steps_completed].each do |step|
            puts "    ✓ #{step.humanize}"
          end

          puts "  Environment ready: #{result[:environment_ready] ? '✅' : '⚠️'}"

          if options[:verbose] && result[:validation_details]
            puts ''
            puts '🔍 Detailed Validation Results:'
            result[:validation_details][:checks].each do |check|
              status_icon = case check[:status]
                            when 'pass' then '✅'
                            when 'warning' then '⚠️'
                            else '❌'
                            end
              puts "  #{status_icon} #{check[:name].capitalize}: #{check[:message]}"
            end
          end
        else
          puts '❌ Development environment setup failed'
          puts "Error: #{result[:error]}" if result[:error]
          puts ''
          puts "Prerequisites validated: #{result[:prerequisites_validated] ? '✅' : '❌'}"

          unless result[:steps_completed].empty?
            puts 'Completed steps:'
            result[:steps_completed].each do |step|
              puts "  ✓ #{step.humanize}"
            end
          end

          puts ''
          puts "💡 Try running 'tcf-platform dev-doctor' for detailed diagnostics"
        end
      rescue StandardError => e
        puts "❌ Setup failed with error: #{e.message}"
        puts ''
        puts '🔧 Troubleshooting:'
        puts '  1. Ensure Docker is installed and running'
        puts '  2. Check that required ports are available'
        puts '  3. Verify Git is installed and SSH keys are configured'
        puts "  4. Run 'tcf-platform dev-doctor' for detailed diagnostics"
      end
    end

    def run_development_tests(service)
      puts '🧪 Running tests for TCF Platform services...'
      puts ''

      begin
        config_manager = TcfPlatform::ConfigManager.load_environment(ENV.fetch('RACK_ENV', 'test'))
        test_coordinator = TcfPlatform::TestCoordinator.new(config_manager)

        if service
          puts "📁 Running tests for specific service: #{service}"
          result = test_coordinator.run_service_tests(service)
          display_service_test_results(result)
        elsif options[:integration]
          puts '🔗 Running integration tests across all services'
          result = test_coordinator.run_integration_tests
          display_integration_test_results(result)
        else
          puts '🏃 Running tests for all TCF services'
          puts "Execution mode: #{options[:parallel] ? 'parallel' : 'sequential'}"
          puts ''

          result = test_coordinator.run_all_tests(parallel: options[:parallel])
          display_comprehensive_test_results(result)
        end
      rescue StandardError => e
        puts "❌ Test execution failed: #{e.message}"
        puts ''
        puts '💡 Troubleshooting:'
        puts '  1. Ensure services are available in sibling directories'
        puts '  2. Check that test dependencies are installed'
        puts '  3. Verify service test suites are properly configured'
      end
    end

    def manage_database_migrations(service)
      puts '🗄️  Managing database migrations for TCF services...'
      puts ''

      begin
        config_manager = TcfPlatform::ConfigManager.load_environment(ENV.fetch('RACK_ENV', 'development'))
        migration_manager = TcfPlatform::MigrationManager.new(config_manager)

        if options[:status]
          puts '📊 Migration Status Report'
          puts '=' * 50

          status = migration_manager.migration_status
          display_migration_status(status)
        elsif options[:rollback] && service
          puts "⏪ Rolling back migrations for #{service}"

          result = migration_manager.rollback_migrations(service, steps: options[:rollback])
          display_rollback_results(result)
        elsif service
          puts "📈 Running migrations for service: #{service}"

          result = migration_manager.migrate_service(service)
          display_service_migration_results(result)
        else
          puts '📈 Running migrations for all TCF services'
          puts ''

          result = migration_manager.migrate_all_databases
          display_comprehensive_migration_results(result)
        end
      rescue StandardError => e
        puts "❌ Migration management failed: #{e.message}"
        puts ''
        puts '💡 Troubleshooting:'
        puts '  1. Ensure database servers are running and accessible'
        puts '  2. Verify database configurations are correct'
        puts '  3. Check that migration files exist in service directories'
        puts '  4. Ensure proper database permissions are configured'
      end
    end

    def run_environment_diagnostics
      puts '🏥 TCF Platform Environment Diagnostics'
      puts '=' * 60
      puts ''

      begin
        dev_environment = TcfPlatform::DevEnvironment.new

        if options[:quick]
          puts '⚡ Quick Health Check'
          status = dev_environment.status

          health_icon = status[:environment_ready] ? '✅' : '❌'
          puts "  #{health_icon} Environment Status: #{status[:environment_ready] ? 'Ready' : 'Not Ready'}"

          overall_health = status[:services_status][:overall_status]
          health_description = case overall_health
                               when 'healthy' then '✅ Healthy'
                               when 'degraded' then '⚠️ Degraded'
                               else '❌ Unhealthy'
                               end
          puts "  #{health_description} Services: #{overall_health}"

          puts ''
          puts 'Run without --quick for comprehensive diagnostics'
          return
        end

        puts '🔍 System Prerequisites'
        puts '-' * 30

        prereq_result = dev_environment.system_checker.prerequisites_met?
        prereq_result[:checks].each do |check|
          status_icon = case check[:status]
                        when 'pass' then '✅'
                        when 'warning' then '⚠️'
                        else '❌'
                        end
          puts "  #{status_icon} #{check[:name].humanize}: #{check[:message]}"
        end

        puts ''
        puts '🐳 Docker Environment'
        puts '-' * 30

        docker_available = dev_environment.system_checker.docker_available?
        compose_available = dev_environment.system_checker.docker_compose_available?

        puts "  #{docker_available ? '✅' : '❌'} Docker: #{docker_available ? 'Available' : 'Not available or not running'}"
        puts "  #{compose_available ? '✅' : '❌'} Docker Compose: #{compose_available ? 'Available' : 'Not available'}"

        puts ''
        puts '🔌 Port Availability'
        puts '-' * 30

        ports_result = dev_environment.system_checker.check_ports
        if ports_result[:available]
          puts '  ✅ All critical ports available'
        else
          puts '  ⚠️ Some ports in use:'
          ports_result[:blocked_ports].each do |port|
            puts "    ❌ Port #{port}: In use"
          end
        end

        puts ''
        puts '📁 Repository Status'
        puts '-' * 30

        repo_status = dev_environment.repository_manager.repository_status
        repo_status.each do |repo_name, info|
          if info[:exists]
            icon = info[:git_repository] ? '✅' : '⚠️'
            status_text = info[:git_repository] ? 'Git repository' : 'Directory exists but not a git repo'
            branch_info = info[:current_branch] ? " (#{info[:current_branch]})" : ''
            clean_status = info[:clean] ? ' - Clean' : ' - Uncommitted changes'
            puts "  #{icon} #{repo_name}: #{status_text}#{branch_info}#{clean_status if info[:git_repository]}"
          else
            puts "  ❌ #{repo_name}: Missing"
          end
        end

        puts ''
        puts '🗄️  Database Configuration'
        puts '-' * 30

        config_manager = dev_environment.config_manager
        db_url = config_manager.database_url
        redis_url = config_manager.redis_url

        puts "  #{db_url ? '✅' : '❌'} PostgreSQL: #{db_url ? 'Configured' : 'Not configured'}"
        puts "  #{redis_url ? '✅' : '❌'} Redis: #{redis_url ? 'Configured' : 'Not configured'}"

        puts ''
        puts '🚀 Service Health'
        puts '-' * 30

        begin
          health_monitor = TcfPlatform::ServiceHealthMonitor.new
          health_status = health_monitor.aggregate_health_status

          puts "  Overall Status: #{health_status[:overall_status].upcase}"
          puts "  Healthy Services: #{health_status[:healthy_count]}/#{health_status[:total_services]}"

          if options[:verbose] && !health_status[:unhealthy_services].empty?
            puts ''
            puts '  Unhealthy Services:'
            health_status[:unhealthy_services].each do |service|
              puts "    ❌ #{service}"
            end
          end
        rescue StandardError => e
          puts "  ⚠️ Service health check failed: #{e.message}"
        end

        puts ''
        puts '📊 Summary'
        puts '-' * 30

        validation_result = dev_environment.validate
        overall_health = validation_result[:valid] ? '✅ Ready for development' : '⚠️ Issues detected'
        puts "  Environment Status: #{overall_health}"

        if options[:verbose]
          puts ''
          puts '🔧 Verbose System Information'
          puts '-' * 40

          system_info = dev_environment.status[:system_info]
          puts "  Platform: #{system_info[:platform]}"
          puts "  Ruby Version: #{system_info[:ruby_version]}"
          puts "  Docker Available: #{system_info[:docker_available] ? 'Yes' : 'No'}"
          puts "  Last Checked: #{system_info[:ports_checked]}"
        end

        unless validation_result[:valid]
          puts ''
          puts '💡 Recommendations:'
          validation_result[:checks].each do |check|
            next if check[:status] == 'pass'

            puts "  • #{check[:name].humanize}: #{check[:message]}"
          end
        end
      rescue StandardError => e
        puts "❌ Diagnostics failed: #{e.message}"
        puts ''
        puts 'This may indicate a serious environment issue.'
        puts 'Try running individual components manually to isolate the problem.'
      end
    end

    # Helper methods for displaying results

    def display_service_test_results(result)
      puts "📋 Test Results for #{result[:service]}"
      puts '-' * 40

      status_icon = case result[:status]
                    when 'success' then '✅'
                    when 'skipped' then '⏭️'
                    else '❌'
                    end

      puts "  #{status_icon} Status: #{result[:status].upcase}"
      puts "  Tests: #{result[:test_count]}"
      puts "  Passed: #{result[:passed]}"
      puts "  Failed: #{result[:failed]}" if result[:failed].positive?
      puts "  Execution Time: #{result[:execution_time]&.round(2)}s" if result[:execution_time]
      puts "  Runner: #{result[:runner]}" if result[:runner]

      puts "  Error: #{result[:error]}" if result[:error]
    end

    def display_integration_test_results(result)
      puts '🔗 Integration Test Results'
      puts '-' * 40

      status_icon = result[:status] == 'success' ? '✅' : '❌'
      puts "  #{status_icon} Overall Status: #{result[:status].upcase}"
      puts "  Dependency Check: #{result[:dependency_check] ? 'Passed' : 'Failed'}"
      puts "  Services Involved: #{result[:services_involved].join(', ')}"
      puts "  Test Suites: #{result[:test_suites].size}"

      return unless options[:verbose] && result[:integration_scenarios]

      puts ''
      puts '  Scenario Results:'
      result[:integration_scenarios].each do |scenario|
        scenario_icon = scenario[:status] == 'success' ? '✅' : '❌'
        puts "    #{scenario_icon} #{scenario[:name]}: #{scenario[:status]}"
      end
    end

    def display_comprehensive_test_results(result)
      puts '📊 Comprehensive Test Results'
      puts '=' * 50

      status_icon = case result[:status]
                    when 'success' then '✅'
                    when 'partial' then '⚠️'
                    else '❌'
                    end

      puts "#{status_icon} Overall Status: #{result[:status].upcase}"
      puts "Execution Mode: #{result[:execution_mode]}"
      puts "Execution Time: #{result[:execution_time].round(2)}s"
      puts ''
      puts 'Test Summary:'
      puts "  Services Tested: #{result[:services_tested].size}"
      puts "  Total Tests: #{result[:total_tests]}"
      puts "  Passed: #{result[:passed_tests]}"
      puts "  Failed: #{result[:failed_tests]}"

      return if result[:failed_services].empty?

      puts ''
      puts 'Failed Services:'
      result[:failed_services].each do |service|
        puts "  ❌ #{service}"
      end
    end

    def display_migration_status(status)
      puts "Overall Status: #{status[:overall_status].upcase}"
      puts "Services with Pending Migrations: #{status[:services_with_pending_migrations]}"
      puts ''

      status[:services].each do |service_name, service_status|
        icon = service_status[:pending_migrations].empty? ? '✅' : '⚠️'
        puts "#{icon} #{service_name}:"
        puts "  Database: #{service_status[:database_name]}"
        puts "  Migration System: #{service_status[:migration_system]}"
        puts "  Pending Migrations: #{service_status[:pending_migrations].size}"
        puts "  Applied Migrations: #{service_status[:applied_migrations].size}"
        puts ''
      end
    end

    def display_service_migration_results(result)
      puts "Migration Results for #{result[:service]}"
      puts '-' * 40

      status_icon = result[:status] == 'success' ? '✅' : '❌'
      puts "#{status_icon} Status: #{result[:status].upcase}"
      puts "Database: #{result[:database_url]}"
      puts "Connectivity: #{result[:connectivity_check] ? 'Success' : 'Failed'}"
      puts "Migrations Applied: #{result[:migrations_applied]}"

      puts "Error: #{result[:error]}" if result[:error]
    end

    def display_comprehensive_migration_results(result)
      puts '📊 Migration Results Summary'
      puts '=' * 50

      status_icon = case result[:status]
                    when 'success' then '✅'
                    when 'partial' then '⚠️'
                    else '❌'
                    end

      puts "#{status_icon} Overall Status: #{result[:status].upcase}"
      puts "Services Processed: #{result[:services_migrated].size}"
      puts "Total Migrations Applied: #{result[:total_migrations_applied]}"
      puts ''

      result[:services_migrated].each do |service_result|
        service_icon = service_result[:status] == 'success' ? '✅' : '❌'
        puts "#{service_icon} #{service_result[:service]}: #{service_result[:status]} (#{service_result[:migrations_applied]} migrations)"
      end
    end

    def display_rollback_results(result)
      puts "Rollback Results for #{result[:service]}"
      puts '-' * 40

      status_icon = result[:status] == 'success' ? '✅' : '❌'
      puts "#{status_icon} Status: #{result[:status].upcase}"
      puts "Steps Rolled Back: #{result[:rollback_steps]}"
      puts "Safety Check: #{result[:safety_check] ? 'Passed' : 'Failed'}"
      puts "Available Rollbacks: #{result[:available_rollbacks].size}"

      puts "Error: #{result[:error]}" if result[:error]
    end
  end
end

# Extension to add humanize method to strings
class String
  def humanize
    gsub('_', ' ').split.map(&:capitalize).join(' ')
  end
end
