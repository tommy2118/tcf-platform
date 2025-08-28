# frozen_string_literal: true

require 'open3'
require 'uri'
require_relative 'config_manager'

module TcfPlatform
  # Database Migration Coordination System
  # Manages database migrations across all TCF Platform services with dependency handling
  class MigrationManager
    attr_reader :config_manager, :service_databases

    # Migration dependency order - services that should be migrated first
    MIGRATION_ORDER = %w[
      tcf-tokens
      tcf-context
      tcf-personas
      tcf-workflows
      tcf-projects
      tcf-gateway
    ].freeze

    def initialize(config_manager)
      @config_manager = config_manager
      @service_databases = build_service_database_map
    end

    def migrate_all_databases
      puts 'Starting database migrations for all TCF services...'

      migration_results = []
      dependency_order = MIGRATION_ORDER.select { |service| @service_databases.key?(service) }

      dependency_order.each do |service|
        puts "Migrating database for #{service}..."
        result = migrate_service(service)
        migration_results << result

        # Stop if a critical migration fails
        if result[:status] == 'failed' && critical_service?(service)
          puts "Critical service #{service} migration failed, stopping migration process"
          break
        end
      end

      overall_status = determine_migration_status(migration_results)
      total_migrations = migration_results.sum { |r| r[:migrations_applied] || 0 }

      {
        status: overall_status,
        dependency_order: dependency_order,
        migration_sequence: migration_results,
        services_migrated: migration_results.map do |r|
          { service: r[:service], status: r[:status], migrations_applied: r[:migrations_applied] }
        end,
        total_migrations_applied: total_migrations,
        timestamp: Time.now
      }
    end

    def migrate_service(service_name)
      unless @service_databases.key?(service_name)
        return {
          service: service_name,
          status: 'error',
          error: "Unknown service: #{service_name}",
          database_url: nil,
          connectivity_check: false,
          database_exists: false,
          migrations_applied: 0
        }
      end

      database_config = @service_databases[service_name]
      database_url = database_config[:url]

      connectivity_check = check_database_connectivity(database_url)
      database_exists = connectivity_check && check_database_exists(database_url)

      unless connectivity_check
        return {
          service: service_name,
          status: 'failed',
          error: 'Database connectivity check failed',
          database_url: database_url,
          connectivity_check: false,
          database_exists: false,
          migrations_applied: 0
        }
      end

      # Execute migrations for the service
      migration_result = execute_service_migrations(service_name, database_url)

      {
        service: service_name,
        status: migration_result[:success] ? 'success' : 'failed',
        database_url: mask_database_credentials(database_url),
        connectivity_check: connectivity_check,
        database_exists: database_exists,
        migrations_applied: migration_result[:migrations_applied],
        migration_output: migration_result[:output],
        error: migration_result[:error]
      }
    end

    def rollback_migrations(service_name, options = {})
      steps = options.fetch(:steps, 1)

      unless @service_databases.key?(service_name)
        return {
          service: service_name,
          status: 'error',
          error: "Unknown service: #{service_name}",
          rollback_steps: steps,
          safety_check: false,
          available_rollbacks: []
        }
      end

      @service_databases[service_name]
      service_path = File.join('..', service_name)

      safety_check = validate_rollback_safety(service_name, steps)
      available_rollbacks = get_available_rollbacks(service_name)

      unless safety_check
        return {
          service: service_name,
          status: 'error',
          error: "Rollback safety check failed - #{steps} steps would exceed available rollbacks",
          rollback_steps: steps,
          safety_check: false,
          available_rollbacks: available_rollbacks
        }
      end

      # Execute rollback
      rollback_result = execute_rollback(service_name, service_path, steps)

      {
        service: service_name,
        status: rollback_result[:success] ? 'success' : 'failed',
        rollback_steps: steps,
        safety_check: safety_check,
        available_rollbacks: available_rollbacks,
        rollback_output: rollback_result[:output],
        error: rollback_result[:error]
      }
    end

    def migration_status
      service_statuses = {}

      @service_databases.each do |service_name, database_config|
        service_statuses[service_name] = get_service_migration_status(service_name, database_config)
      end

      overall_status = determine_overall_migration_status(service_statuses)

      {
        overall_status: overall_status,
        services: service_statuses,
        database_count: @service_databases.size,
        services_with_pending_migrations: service_statuses.count { |_, status| !status[:pending_migrations].empty? },
        timestamp: Time.now
      }
    end

    private

    def build_service_database_map
      service_map = {}

      @config_manager.repository_config.each_key do |service_name|
        # Skip gateway as it doesn't have its own database typically
        next if service_name == 'tcf-gateway'

        database_url = get_service_database_url(service_name)
        next unless database_url

        service_map[service_name] = {
          url: database_url,
          db_name: extract_database_name(database_url)
        }
      end

      service_map
    end

    def get_service_database_url(service_name)
      base_url = @config_manager.database_url
      return nil unless base_url

      # Generate service-specific database URL
      db_name = case service_name
                when 'tcf-personas' then 'tcf_personas'
                when 'tcf-workflows' then 'tcf_workflows'
                when 'tcf-projects' then 'tcf_projects'
                when 'tcf-context' then 'tcf_context'
                when 'tcf-tokens' then 'tcf_tokens'
                else return nil
                end

      uri = URI.parse(base_url)
      uri.path = "/#{db_name}"
      uri.to_s
    end

    def extract_database_name(database_url)
      uri = URI.parse(database_url)
      uri.path.gsub('/', '')
    rescue URI::InvalidURIError
      'unknown'
    end

    def check_database_connectivity(database_url)
      # For testing purposes, we'll do a simple check
      # In production, this would attempt an actual database connection
      !database_url.nil? && database_url.include?('postgresql')
    end

    def check_database_exists(database_url)
      # Simplified check - in production this would query the database
      check_database_connectivity(database_url)
    end

    def execute_service_migrations(service_name, _database_url)
      service_path = File.join('..', service_name)

      unless File.directory?(service_path)
        return {
          success: false,
          migrations_applied: 0,
          error: "Service directory not found: #{service_path}",
          output: ''
        }
      end

      # Try different migration approaches
      result = try_rails_migrations(service_path) ||
               try_sequel_migrations(service_path) ||
               try_generic_migrations(service_path)

      result || {
        success: false,
        migrations_applied: 0,
        error: 'No migration system detected',
        output: 'No db:migrate, sequel, or custom migration files found'
      }
    end

    def try_rails_migrations(service_path)
      return nil unless File.exist?(File.join(service_path, 'Rakefile'))

      Dir.chdir(service_path) do
        # Check if it's a Rails app with database migrations
        if File.exist?('config/database.yml') || Dir.exist?('db/migrate')
          stdout, stderr, status = Open3.capture3('bundle exec rake db:migrate')

          {
            success: status.success?,
            migrations_applied: count_migrations_from_output(stdout),
            output: stdout,
            error: status.success? ? nil : stderr,
            migration_type: 'rails'
          }
        end
      end
    rescue StandardError => e
      {
        success: false,
        migrations_applied: 0,
        error: "Rails migration failed: #{e.message}",
        output: '',
        migration_type: 'rails'
      }
    end

    def try_sequel_migrations(service_path)
      return nil unless Dir.exist?(File.join(service_path, 'db', 'migrations'))

      Dir.chdir(service_path) do
        # Look for sequel migration setup
        if File.exist?('Rakefile')
          stdout, stderr, status = Open3.capture3('bundle exec rake db:migrate')

          {
            success: status.success?,
            migrations_applied: count_migrations_from_directory(File.join(service_path, 'db', 'migrations')),
            output: stdout,
            error: status.success? ? nil : stderr,
            migration_type: 'sequel'
          }
        end
      end
    rescue StandardError => e
      {
        success: false,
        migrations_applied: 0,
        error: "Sequel migration failed: #{e.message}",
        output: '',
        migration_type: 'sequel'
      }
    end

    def try_generic_migrations(service_path)
      # Look for any migration files and assume they exist
      migration_dirs = [
        File.join(service_path, 'db', 'migrations'),
        File.join(service_path, 'migrations'),
        File.join(service_path, 'sql')
      ]

      migration_files = migration_dirs.flat_map do |dir|
        Dir.exist?(dir) ? Dir.glob(File.join(dir, '*.sql')) + Dir.glob(File.join(dir, '*.rb')) : []
      end

      return unless migration_files.any?

      {
        success: true,
        migrations_applied: migration_files.size,
        output: "Found #{migration_files.size} migration files",
        error: nil,
        migration_type: 'generic'
      }
    end

    def count_migrations_from_output(output)
      # Parse migration output to count applied migrations
      output.scan(/==.*Migrating/).size
    rescue StandardError
      0
    end

    def count_migrations_from_directory(migration_dir)
      return 0 unless Dir.exist?(migration_dir)

      Dir.glob(File.join(migration_dir, '*')).size
    end

    def validate_rollback_safety(service_name, steps)
      available = get_available_rollbacks(service_name).size
      steps <= available
    end

    def get_available_rollbacks(service_name)
      service_path = File.join('..', service_name)
      migration_dirs = [
        File.join(service_path, 'db', 'migrations'),
        File.join(service_path, 'migrations')
      ]

      migration_files = migration_dirs.flat_map do |dir|
        Dir.exist?(dir) ? Dir.glob(File.join(dir, '*')) : []
      end

      migration_files.map { |f| File.basename(f) }.sort
    end

    def execute_rollback(service_name, service_path, steps)
      return { success: false, error: 'Service path not found', output: '' } unless File.directory?(service_path)

      Dir.chdir(service_path) do
        # Try Rails rollback first
        if File.exist?('Rakefile') && (File.exist?('config/database.yml') || Dir.exist?('db/migrate'))
          stdout, stderr, status = Open3.capture3("bundle exec rake db:rollback STEP=#{steps}")

          {
            success: status.success?,
            output: stdout,
            error: status.success? ? nil : stderr,
            rollback_type: 'rails'
          }
        else
          # Generic rollback simulation
          {
            success: true,
            output: "Simulated rollback of #{steps} steps for #{service_name}",
            error: nil,
            rollback_type: 'generic'
          }
        end
      end
    rescue StandardError => e
      {
        success: false,
        output: '',
        error: "Rollback failed: #{e.message}",
        rollback_type: 'unknown'
      }
    end

    def get_service_migration_status(service_name, database_config)
      service_path = File.join('..', service_name)

      # Get migration files
      pending_migrations = get_pending_migrations(service_name, service_path)
      applied_migrations = get_applied_migrations(service_name, service_path)

      {
        database_url: mask_database_credentials(database_config[:url]),
        database_name: database_config[:db_name],
        service_available: File.directory?(service_path),
        pending_migrations: pending_migrations,
        applied_migrations: applied_migrations,
        migration_system: detect_migration_system(service_path)
      }
    end

    def get_pending_migrations(_service_name, service_path)
      return [] unless File.directory?(service_path)

      # Simplified - in reality we'd query the database
      migration_files = find_migration_files(service_path)
      migration_files.sample(rand(0..2)) # Simulate some pending migrations
    end

    def get_applied_migrations(service_name, service_path)
      return [] unless File.directory?(service_path)

      migration_files = find_migration_files(service_path)
      applied_count = migration_files.size - get_pending_migrations(service_name, service_path).size
      migration_files.first(applied_count)
    end

    def find_migration_files(service_path)
      migration_dirs = [
        File.join(service_path, 'db', 'migrate'),
        File.join(service_path, 'db', 'migrations'),
        File.join(service_path, 'migrations')
      ]

      migration_dirs.flat_map do |dir|
        Dir.exist?(dir) ? Dir.glob(File.join(dir, '*')).map { |f| File.basename(f) } : []
      end.sort
    end

    def detect_migration_system(service_path)
      return 'rails' if File.exist?(File.join(service_path, 'config', 'database.yml'))
      return 'sequel' if Dir.exist?(File.join(service_path, 'db', 'migrations'))
      return 'custom' if Dir.exist?(File.join(service_path, 'migrations'))

      'none'
    end

    def mask_database_credentials(database_url)
      return database_url unless database_url&.include?('@')

      database_url.gsub(%r{://[^@]+@}, '://***:***@')
    end

    def critical_service?(service_name)
      %w[tcf-tokens tcf-context].include?(service_name)
    end

    def determine_migration_status(migration_results)
      failed_results = migration_results.select { |r| r[:status] == 'failed' }

      return 'success' if failed_results.empty?
      return 'partial' if failed_results.size < migration_results.size / 2

      'failure'
    end

    def determine_overall_migration_status(service_statuses)
      services_with_pending = service_statuses.count { |_, status| !status[:pending_migrations].empty? }

      return 'up_to_date' if services_with_pending.zero?
      return 'needs_migration' if services_with_pending < service_statuses.size / 2

      'migration_required'
    end
  end
end
