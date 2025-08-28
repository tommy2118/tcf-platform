# frozen_string_literal: true

require_relative 'system_checker'
require_relative 'docker_manager'
require_relative 'config_manager'
require_relative 'repository_manager'
require_relative 'service_health_monitor'

module TcfPlatform
  # Development Environment Management
  # Coordinates setup, validation, and management of the complete TCF development environment
  class DevEnvironment
    attr_reader :system_checker, :docker_manager, :config_manager, :repository_manager

    def initialize
      @system_checker = SystemChecker.new
      @docker_manager = DockerManager.new
      @config_manager = ConfigManager.load_environment('development')
      @repository_manager = RepositoryManager.new(@config_manager)
      @service_health_monitor = ServiceHealthMonitor.new
    end

    def setup
      puts 'Setting up TCF development environment...'

      # Validate prerequisites first
      prereq_result = @system_checker.prerequisites_met?
      unless prereq_result[:met]
        return {
          status: 'error',
          error: "Prerequisites not met: #{prereq_result[:checks].reject do |c|
            c[:status] == 'pass'
          end.map { |c| c[:message] }.join(', ')}",
          prerequisites_validated: false,
          steps_completed: [],
          environment_ready: false
        }
      end

      steps_completed = []

      # Step 1: Docker availability check
      if @system_checker.docker_available?
        steps_completed << 'docker_check'
        puts '✓ Docker is available'
      else
        return {
          status: 'error',
          error: 'Docker is not available or not running',
          prerequisites_validated: false,
          steps_completed: steps_completed,
          environment_ready: false
        }
      end

      # Step 2: Clone repositories if needed
      begin
        @repository_manager.ensure_all_repositories
        steps_completed << 'repositories_cloned'
        puts '✓ Repositories verified/cloned'
      rescue StandardError => e
        puts "⚠ Repository setup warning: #{e.message}"
        # Continue setup even if repos have issues
      end

      # Step 3: Configure services
      begin
        setup_service_configurations
        steps_completed << 'services_configured'
        puts '✓ Service configurations ready'
      rescue StandardError => e
        puts "⚠ Service configuration warning: #{e.message}"
      end

      # Step 4: Validate final setup
      validation_result = validate
      environment_ready = validation_result[:valid]

      {
        status: 'success',
        prerequisites_validated: true,
        steps_completed: steps_completed,
        environment_ready: environment_ready,
        validation_details: validation_result
      }
    end

    def validate
      puts 'Validating development environment...'

      checks = []
      all_valid = true

      # Docker validation
      docker_check = validate_docker
      checks << docker_check
      all_valid = false unless docker_check[:status] == 'pass'

      # Repository validation
      repo_check = validate_repositories
      checks << repo_check
      all_valid = false unless repo_check[:status] == 'pass'

      # Database validation
      db_check = validate_database
      checks << db_check
      all_valid = false unless db_check[:status] == 'pass'

      # Redis validation
      redis_check = validate_redis
      checks << redis_check
      all_valid = false unless redis_check[:status] == 'pass'

      # Services validation
      services_check = validate_services
      checks << services_check
      all_valid = false unless services_check[:status] == 'pass'

      {
        valid: all_valid,
        checks: checks,
        timestamp: Time.now
      }
    end

    def status
      health_status = @service_health_monitor.aggregate_health_status
      validation_result = validate

      {
        environment_ready: validation_result[:valid],
        services_status: health_status,
        last_validation: validation_result[:timestamp],
        system_info: system_information
      }
    end

    private

    def setup_service_configurations
      # Ensure docker-compose.yml exists or generate it
      compose_file = File.join(Dir.pwd, 'docker-compose.yml')
      puts 'Docker Compose file not found, this is expected in development' unless File.exist?(compose_file)

      # Validate environment variables
      @config_manager.validate!
    rescue TcfPlatform::ConfigurationError => e
      puts "Configuration warning: #{e.message}"
    end

    def validate_docker
      if @system_checker.docker_available? && @system_checker.docker_compose_available?
        { name: 'docker', status: 'pass', message: 'Docker and Docker Compose available' }
      else
        { name: 'docker', status: 'fail', message: 'Docker or Docker Compose not available' }
      end
    end

    def validate_repositories
      # Check if we can access repository configurations
      repo_config = @config_manager.repository_config
      missing_repos = []

      repo_config.each_key do |repo_name|
        repo_path = File.join('..', repo_name)
        missing_repos << repo_name unless File.directory?(repo_path)
      end

      if missing_repos.empty?
        { name: 'repositories', status: 'pass', message: 'All repositories available' }
      else
        { name: 'repositories', status: 'warning', message: "Missing repositories: #{missing_repos.join(', ')}" }
      end
    end

    def validate_database
      # For development, we check if database URL is configured
      db_url = @config_manager.database_url
      if db_url&.include?('postgresql')
        { name: 'database', status: 'pass', message: 'Database configuration valid' }
      else
        { name: 'database', status: 'warning', message: 'Database configuration missing or invalid' }
      end
    end

    def validate_redis
      redis_url = @config_manager.redis_url
      if redis_url&.include?('redis')
        { name: 'redis', status: 'pass', message: 'Redis configuration valid' }
      else
        { name: 'redis', status: 'warning', message: 'Redis configuration missing or invalid' }
      end
    end

    def validate_services
      # Check if services can be queried
      service_status = @docker_manager.service_status
      if service_status.any?
        running_services = service_status.select { |_, status| status[:status] == 'running' }.size
        { name: 'services', status: 'pass', message: "#{running_services} services accessible" }
      else
        { name: 'services', status: 'warning', message: 'No services currently running' }
      end
    rescue StandardError => e
      { name: 'services', status: 'fail', message: "Service check failed: #{e.message}" }
    end

    def system_information
      {
        platform: RUBY_PLATFORM,
        ruby_version: RUBY_VERSION,
        docker_available: @system_checker.docker_available?,
        ports_checked: Time.now
      }
    end
  end
end
