# frozen_string_literal: true

require 'yaml'
require 'uri'
require 'pathname'

module TcfPlatform
  class ConfigurationError < StandardError; end
  class CircularDependencyError < StandardError; end

  class ConfigManager
    REQUIRED_PRODUCTION_VARS = %w[DATABASE_URL JWT_SECRET REDIS_URL].freeze

    SERVICE_PORTS = {
      'tcf-gateway' => 3000,
      'tcf-personas' => 3001,
      'tcf-workflows' => 3002,
      'tcf-projects' => 3003,
      'tcf-context' => 3004,
      'tcf-tokens' => 3005
    }.freeze

    def self.load_environment(env = nil)
      env ||= ENV.fetch('RACK_ENV', 'development')
      Config.new(env)
    end
  end

  class Config
    attr_reader :environment

    def initialize(env)
      @environment = env
      @config = load_config
      # Validate critical production variables during construction
      validate_production_on_load! if @environment == 'production'
    end

    def database_url
      @config['database_url'] || generate_database_url
    end

    def redis_url
      @config['redis_url'] || 'redis://localhost:6379/0'
    end

    def jwt_secret
      @config['jwt_secret'] || 'development-secret'
    end

    def from_env_file?
      true
    end

    def service_config(service_name)
      unless ConfigManager::SERVICE_PORTS.key?(service_name)
        available_services = ConfigManager::SERVICE_PORTS.keys.join(', ')
        raise ConfigurationError, "Unknown service: #{service_name}. Available services: #{available_services}"
      end

      port = ConfigManager::SERVICE_PORTS[service_name]
      {
        port: port,
        environment: build_service_environment(service_name)
      }
    end

    def docker_compose_config
      services = {}

      ConfigManager::SERVICE_PORTS.each_key do |service_name|
        services[service_name] = {
          'environment' => build_service_environment(service_name),
          'depends_on' => build_service_dependencies(service_name)
        }
      end

      { 'services' => services }
    end

    def validate!
      validate_required_production_vars_comprehensive! if @environment == 'production'
      validate_database_url!
      validate_redis_url!
    end

    def reload!
      @config = load_config
    end

    def repository_config
      {
        'tcf-gateway' => {
          'url' => 'git@github.com:tommy2118/tcf-gateway.git',
          'branch' => 'master',
          'required' => true
        },
        'tcf-personas' => {
          'url' => 'git@github.com:tommy2118/tcf-personas.git',
          'branch' => 'master',
          'required' => true
        },
        'tcf-workflows' => {
          'url' => 'git@github.com:tommy2118/tcf-workflows.git',
          'branch' => 'master',
          'required' => true
        },
        'tcf-projects' => {
          'url' => 'git@github.com:tommy2118/tcf-projects.git',
          'branch' => 'master',
          'required' => true
        },
        'tcf-context' => {
          'url' => 'git@github.com:tommy2118/tcf-context.git',
          'branch' => 'master',
          'required' => true
        },
        'tcf-tokens' => {
          'url' => 'git@github.com:tommy2118/tcf-tokens.git',
          'branch' => 'master',
          'required' => true
        }
      }
    end

    private

    def validate_production_on_load!
      missing_vars = ConfigManager::REQUIRED_PRODUCTION_VARS.select do |var|
        ENV[var].nil? || ENV[var].empty?
      end

      # Validate if multiple required variables are missing
      return unless missing_vars.length >= 2

      raise ConfigurationError, "Missing required environment variables: #{missing_vars.join(', ')}"
    end

    def validate_critical_production_vars!
      missing_vars = ConfigManager::REQUIRED_PRODUCTION_VARS.select do |var|
        ENV[var].nil? || ENV[var].empty?
      end

      # Only raise during construction if we're missing ALL required variables
      # This handles the case where production environment is completely unconfigured
      # Partial misconfigurations are caught by validate!
      return unless missing_vars.length == ConfigManager::REQUIRED_PRODUCTION_VARS.length

      raise ConfigurationError, "Missing required environment variables: #{missing_vars.join(', ')}"
    end

    def validate_required_production_vars_comprehensive!
      missing_vars = ConfigManager::REQUIRED_PRODUCTION_VARS.select do |var|
        ENV[var].nil? || ENV[var].empty?
      end

      return if missing_vars.empty?

      raise ConfigurationError, "Missing required environment variables: #{missing_vars.join(', ')}"
    end

    def load_config
      config = {}

      # Load from environment variables
      config['database_url'] = ENV.fetch('DATABASE_URL', nil)
      config['redis_url'] = ENV.fetch('REDIS_URL', nil)
      config['jwt_secret'] = ENV.fetch('JWT_SECRET', nil)
      config['openai_api_key'] = ENV.fetch('OPENAI_API_KEY', nil)
      config['anthropic_api_key'] = ENV.fetch('ANTHROPIC_API_KEY', nil)
      config['qdrant_url'] = ENV['QDRANT_URL'] || 'http://localhost:6333'

      # Remove nil values
      config.compact
    end

    def generate_database_url
      case @environment
      when 'test'
        'postgresql://tcf:password@localhost:5432/tcf_platform_test'
      when 'production'
        ENV['DATABASE_URL'] || raise(ConfigurationError, 'DATABASE_URL required in production')
      else
        'postgresql://tcf:password@localhost:5432/tcf_platform_development'
      end
    end

    def build_service_environment(service_name)
      env = {}

      # Common environment variables
      env['JWT_SECRET'] = jwt_secret
      env['REDIS_URL'] = service_redis_url(service_name)

      case service_name
      when 'tcf-gateway'
        # Gateway needs service discovery URLs
        env.merge!(service_discovery_urls)
      when 'tcf-personas'
        env['DATABASE_URL'] = service_database_url('tcf_personas')
        env['TCF_CONTEXT_URL'] = 'http://context:3004'
        env['TCF_TOKENS_URL'] = 'http://tokens:3005'
        env['CLAUDE_HOME'] = '/root/.claude'
      when 'tcf-workflows'
        env['DATABASE_URL'] = service_database_url('tcf_workflows')
        env['TCF_PERSONAS_URL'] = 'http://personas:3001'
        env['TCF_CONTEXT_URL'] = 'http://context:3004'
        env['TCF_TOKENS_URL'] = 'http://tokens:3005'
      when 'tcf-projects'
        env['DATABASE_URL'] = service_database_url('tcf_projects')
        env['TCF_CONTEXT_URL'] = 'http://context:3004'
        env['TCF_TOKENS_URL'] = 'http://tokens:3005'
        env['S3_BUCKET'] = 'tcf-artifacts'
      when 'tcf-context'
        env['DATABASE_URL'] = service_database_url('tcf_context')
        env['QDRANT_URL'] = @config['qdrant_url'] || 'http://qdrant:6333'
        env['OPENAI_API_KEY'] = @config['openai_api_key'] || ENV['OPENAI_API_KEY'] || nil
      when 'tcf-tokens'
        env['DATABASE_URL'] = service_database_url('tcf_tokens')
      end

      env
    end

    def service_database_url(db_name)
      base_url = database_url
      return base_url unless base_url

      # Replace the database name in the URL
      uri = URI.parse(base_url)
      uri.path = "/#{db_name}"
      uri.to_s
    end

    def service_redis_url(service_name)
      base_redis = redis_url
      return base_redis unless base_redis

      # Assign different Redis database numbers to each service
      db_number = case service_name
                  when 'tcf-gateway' then 0
                  when 'tcf-personas' then 1
                  when 'tcf-workflows' then 2
                  when 'tcf-projects' then 3
                  when 'tcf-context' then 4
                  when 'tcf-tokens' then 5
                  else 0
                  end

      uri = URI.parse(base_redis)
      uri.path = "/#{db_number}"
      uri.to_s
    end

    def service_discovery_urls
      {
        'TCF_PERSONAS_URL' => 'http://personas:3001',
        'TCF_WORKFLOWS_URL' => 'http://workflows:3002',
        'TCF_PROJECTS_URL' => 'http://projects:3003',
        'TCF_CONTEXT_URL' => 'http://context:3004',
        'TCF_TOKENS_URL' => 'http://tokens:3005'
      }
    end

    def build_service_dependencies(service_name)
      deps = ['redis']

      case service_name
      when 'tcf-gateway'
        deps.push('personas', 'workflows', 'projects', 'context', 'tokens')
      when 'tcf-personas', 'tcf-workflows', 'tcf-projects', 'tcf-tokens'
        deps << 'postgres'
      when 'tcf-context'
        deps.push('postgres', 'qdrant')
      end

      deps
    end

    def validate_database_url!
      url = database_url
      return unless url

      begin
        uri = URI.parse(url)
        raise ConfigurationError, 'Invalid DATABASE_URL: must use postgresql scheme' unless uri.scheme == 'postgresql'
      rescue URI::InvalidURIError
        raise ConfigurationError, 'Invalid DATABASE_URL: malformed URL'
      end
    end

    def validate_redis_url!
      url = redis_url
      return unless url

      begin
        uri = URI.parse(url)
        raise ConfigurationError, 'Invalid REDIS_URL: must use redis scheme' unless uri.scheme == 'redis'
      rescue URI::InvalidURIError
        raise ConfigurationError, 'Invalid REDIS_URL: malformed URL'
      end
    end

    def build_dependencies
      {
        'tcf-gateway' => %w[tcf-personas tcf-workflows tcf-projects tcf-context tcf-tokens],
        'tcf-personas' => [],
        'tcf-workflows' => ['tcf-personas'],
        'tcf-projects' => ['tcf-context'],
        'tcf-context' => [],
        'tcf-tokens' => []
      }
    end
  end
end
