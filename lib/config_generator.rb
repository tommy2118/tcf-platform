# frozen_string_literal: true

require 'erb'
require 'fileutils'
require 'yaml'
require_relative 'config_manager'

module TcfPlatform
  class ConfigGenerator
    SUPPORTED_ENVIRONMENTS = %w[development production test].freeze

    attr_reader :environment, :template_path

    def initialize(environment)
      raise ConfigurationError, 'Environment cannot be nil' if environment.nil?

      unless SUPPORTED_ENVIRONMENTS.include?(environment)
        raise ConfigurationError,
              "Unsupported environment: #{environment}. Supported: #{SUPPORTED_ENVIRONMENTS.join(', ')}"
      end

      @environment = environment
      @template_path = File.join(TcfPlatform.root, 'config', 'templates')
      @config_manager = ConfigManager.load_environment(environment)
    end

    def generate_compose_file
      validate_required_template_variables
      render_template('docker-compose.yml.erb')
    end

    def generate_env_file
      render_template("env.#{environment}.erb")
    end

    def generate_nginx_config
      render_template('nginx.conf.erb')
    end

    def generate_k8s_manifests
      render_template('k8s/deployment.yml.erb')
    end

    def template_variables
      vars = {
        environment: environment,
        database_password: environment_database_password,
        jwt_secret: environment_jwt_secret,
        gateway_url: 'http://localhost:3000',
        personas_url: 'http://localhost:3001'
      }

      # Add service discovery URLs
      vars.merge!(service_discovery_variables)

      vars
    end

    def validate_templates
      required_templates = [
        'docker-compose.yml.erb',
        "env.#{environment}.erb",
        'nginx.conf.erb',
        'k8s/deployment.yml.erb'
      ]

      required_templates.each do |template|
        template_file = File.join(@template_path, template)
        raise ConfigurationError, "Template file not found: #{template_file}" unless File.exist?(template_file)

        # Validate template syntax
        begin
          template_content = File.read(template_file)
          erb = ERB.new(template_content)
          # Force compilation to catch syntax errors - just compile, don't evaluate
          erb.src
        rescue StandardError, ScriptError => e
          raise ConfigurationError, "Invalid template syntax in #{template}: #{e.message}"
        end
      end
    end

    def write_configs(output_dir, options = {})
      FileUtils.mkdir_p(output_dir)

      # Write docker-compose.yml
      compose_file = File.join(output_dir, 'docker-compose.yml')
      write_file_with_options(compose_file, generate_compose_file, options)

      # Write .env file
      env_file = File.join(output_dir, '.env')
      write_file_with_options(env_file, generate_env_file, options)

      # Write nginx.conf
      nginx_file = File.join(output_dir, 'nginx.conf')
      write_file_with_options(nginx_file, generate_nginx_config, options)

      # Write k8s manifests (production only)
      return unless environment == 'production'

      k8s_dir = File.join(output_dir, 'k8s')
      FileUtils.mkdir_p(k8s_dir)
      k8s_file = File.join(k8s_dir, 'deployment.yml')
      write_file_with_options(k8s_file, generate_k8s_manifests, options)
    end

    private

    def render_template(template_name)
      template_file = File.join(@template_path, template_name)

      raise ConfigurationError, "Template file not found: #{template_file}" unless File.exist?(template_file)

      template_content = File.read(template_file)
      erb = ERB.new(template_content)

      # Create binding with template variables available
      template_binding = create_template_binding
      erb.result(template_binding)
    end

    def create_template_binding
      # Get template variables
      vars = template_variables

      # Create a clean binding with template variables as local variables
      template_binding = binding

      # Define local variables in the binding for ERB to access
      vars.each do |key, value|
        template_binding.local_variable_set(key, value)
      end

      template_binding
    end

    def validate_required_template_variables
      vars = template_variables
      required_vars = %i[environment database_password jwt_secret]

      missing_vars = required_vars.select { |var| vars[var].nil? || vars[var].empty? }

      return if missing_vars.empty?

      raise ConfigurationError, "Missing template variables: #{missing_vars.join(', ')}"
    end

    def environment_database_password
      case environment
      when 'development'
        'development_password'
      when 'test'
        'test_password'
      when 'production'
        '${SECURE_POSTGRES_PASSWORD}'
      else
        'password'
      end
    end

    def environment_jwt_secret
      case environment
      when 'development'
        'development-jwt-secret'
      when 'test'
        'test-jwt-secret'
      when 'production'
        '${SECURE_JWT_SECRET}'
      else
        'default-secret'
      end
    end

    def service_discovery_variables
      {
        tcf_personas_url: 'http://personas:3001',
        tcf_workflows_url: 'http://workflows:3002',
        tcf_projects_url: 'http://projects:3003',
        tcf_context_url: 'http://context:3004',
        tcf_tokens_url: 'http://tokens:3005'
      }
    end

    def write_file_with_options(file_path, content, options)
      if File.exist?(file_path) && !options[:force] && !options[:force]
        # In real implementation, this might prompt the user
        # For tests, we'll just overwrite if force is true
        return
      end

      File.write(file_path, content)
    end
  end
end
