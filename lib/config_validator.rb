# frozen_string_literal: true

require_relative 'config_manager'
require_relative 'configuration_exceptions'
require_relative 'performance_optimizer'

module TcfPlatform
  # Comprehensive configuration validation with security checks
  class ConfigValidator
    SECURITY_PATTERNS = [
      /password/i,
      /secret/i,
      /token/i,
      /key/i,
      /api[_-]?key/i,
      /auth/i
    ].freeze

    DEFAULT_PASSWORDS = %w[
      password
      123456
      admin
      root
      default
      changeme
    ].freeze

    attr_reader :environment, :config_manager

    def initialize(environment, config_manager = nil)
      @environment = environment
      @config_manager = config_manager || ConfigManager.load_environment(environment)
    end

    def validate_all
      PerformanceOptimizer.with_caching("validation_#{environment}_#{config_cache_key}") do
        errors = []
        errors.concat(validate_file_existence)
        errors.concat(validate_environment_variables)
        errors.concat(validate_security_requirements) if environment == 'production'
        errors.concat(validate_service_configuration)
        errors.concat(validate_network_configuration)
        errors
      end
    end

    def validate_file_existence
      errors = []
      expected_files = expected_configuration_files

      expected_files.each do |file_path|
        full_path = File.join(TcfPlatform.root, file_path)
        errors << "Missing configuration file: #{file_path}" unless File.exist?(full_path)
      end

      errors
    end

    def validate_environment_variables
      errors = []

      case environment
      when 'production'
        errors.concat(validate_production_environment_variables)
      when 'development'
        errors.concat(validate_development_environment_variables)
      when 'test'
        errors.concat(validate_test_environment_variables)
      end

      errors
    end

    def validate_security_requirements
      errors = []
      errors.concat(detect_insecure_passwords)
      errors.concat(validate_tls_configuration)
      errors.concat(validate_secrets_management)
      errors
    end

    def validate_service_configuration
      errors = []

      ConfigManager::SERVICE_PORTS.each do |service_name, expected_port|
        service_config = config_manager.service_config(service_name)

        unless service_config[:port] == expected_port
          errors << "Invalid port configuration for #{service_name}: " \
                     "expected #{expected_port}, got #{service_config[:port]}"
        end
      rescue ConfigurationError => e
        errors << "Service configuration error for #{service_name}: #{e.message}"
      end

      errors
    end

    def validate_network_configuration
      errors = []
      errors.concat(validate_port_conflicts)
      errors.concat(validate_service_connectivity)
      errors
    end

    def security_scan
      findings = []
      findings.concat(scan_for_secrets)
      findings.concat(scan_for_weak_passwords)
      findings.concat(scan_for_insecure_configurations)
      findings
    end

    private

    def config_cache_key
      # Create a cache key based on relevant config state
      key_parts = [
        environment,
        File.mtime(File.join(TcfPlatform.root, 'docker-compose.yml')).to_i
      ]

      # Add environment variables hash
      env_hash = ENV.to_h.select { |k, _| k.start_with?('TCF_', 'DATABASE_', 'REDIS_', 'JWT_') }.hash
      key_parts << env_hash

      key_parts.join('_')
    rescue StandardError
      # Fallback if file doesn't exist or other issues
      "#{environment}_#{Time.now.to_i / 300}" # 5-minute cache
    end

    def expected_configuration_files
      case environment
      when 'development'
        %w[docker-compose.yml .env.development docker-compose.override.yml]
      when 'production'
        %w[docker-compose.yml .env.production docker-compose.prod.yml]
      when 'test'
        %w[docker-compose.test.yml .env.test]
      else
        []
      end
    end

    def validate_production_environment_variables
      errors = []
      missing_vars = ConfigManager::REQUIRED_PRODUCTION_VARS.select do |var|
        ENV[var].nil? || ENV[var].empty?
      end

      unless missing_vars.empty?
        errors << "Missing required production environment variables: #{missing_vars.join(', ')}"
      end

      errors
    end

    def validate_development_environment_variables
      errors = []
      # Development has more relaxed requirements
      %w[DATABASE_URL REDIS_URL].each do |var|
        if ENV[var].nil? || ENV[var].empty?
          # Just warn for development
          errors << "Development environment variable not set: #{var} (using defaults)"
        end
      end
      errors
    end

    def validate_test_environment_variables
      errors = []
      # Test environment should be self-contained
      errors << 'RACK_ENV should be set to "test" for test environment' if ENV['RACK_ENV'] != 'test'
      errors
    end

    def detect_insecure_passwords
      errors = []

      %w[DATABASE_URL JWT_SECRET REDIS_URL].each do |var|
        value = ENV.fetch(var, nil)
        next unless value

        DEFAULT_PASSWORDS.each do |weak_password|
          if value.downcase.include?(weak_password)
            errors << "Weak password detected in #{var}"
            break
          end
        end
      end

      errors
    end

    def validate_tls_configuration
      errors = []

      if environment == 'production'
        # Check for HTTPS configuration
        errors << 'TLS/SSL not enforced in production environment' unless ENV['FORCE_SSL'] == 'true'

        # Check certificate configuration
        cert_vars = %w[SSL_CERT_PATH SSL_KEY_PATH]
        cert_vars.each do |var|
          errors << "Missing SSL certificate configuration: #{var}" if ENV[var].nil? || ENV[var].empty?
        end
      end

      errors
    end

    def validate_secrets_management
      errors = []

      if environment == 'production'
        # Check if secrets are properly externalized
        SECURITY_PATTERNS.each do |pattern|
          ENV.each do |key, value|
            next unless key.match?(pattern) && !value.nil?

            errors << "Short secret detected in #{key}: minimum 16 characters required" if value.length < 16

            if value.match?(/^[a-z]+$/i) || value.match?(/^\d+$/)
              errors << "Weak secret pattern in #{key}: use mixed alphanumeric with special characters"
            end
          end
        end
      end

      errors
    end

    def validate_port_conflicts
      errors = []
      used_ports = []

      ConfigManager::SERVICE_PORTS.each_value do |port|
        if used_ports.include?(port)
          errors << "Port conflict detected: #{port} is used by multiple services"
        else
          used_ports << port
        end
      end

      errors
    end

    def validate_service_connectivity
      errors = []

      # Validate service URLs are properly configured
      %w[TCF_PERSONAS_URL TCF_WORKFLOWS_URL TCF_PROJECTS_URL TCF_CONTEXT_URL TCF_TOKENS_URL].each do |var|
        value = ENV.fetch(var, nil)
        errors << "Invalid service URL in #{var}: #{value}" if value && !valid_url?(value)
      end

      errors
    end

    def scan_for_secrets
      findings = []

      ENV.each do |key, value|
        next unless value

        SECURITY_PATTERNS.each do |pattern|
          next unless key.match?(pattern)

          findings << {
            type: 'potential_secret',
            location: "Environment variable: #{key}",
            severity: 'high',
            message: 'Potential secret found in environment variable'
          }
          break
        end
      end

      findings
    end

    def scan_for_weak_passwords
      findings = []

      %w[DATABASE_URL JWT_SECRET].each do |var|
        value = ENV.fetch(var, nil)
        next unless value

        DEFAULT_PASSWORDS.each do |weak_password|
          next unless value.downcase.include?(weak_password)

          findings << {
            type: 'weak_password',
            location: "Environment variable: #{var}",
            severity: 'critical',
            message: "Weak/default password detected: #{weak_password}"
          }
        end
      end

      findings
    end

    def scan_for_insecure_configurations
      findings = []

      if environment == 'production'
        # Check for debug modes enabled
        if ENV['DEBUG'] == 'true' || ENV['RACK_ENV'] == 'development'
          findings << {
            type: 'insecure_config',
            location: 'Environment configuration',
            severity: 'high',
            message: 'Debug mode enabled in production environment'
          }
        end

        # Check for permissive CORS
        if ENV['CORS_ALLOW_ALL'] == 'true'
          findings << {
            type: 'insecure_config',
            location: 'CORS configuration',
            severity: 'medium',
            message: 'Permissive CORS policy detected in production'
          }
        end
      end

      findings
    end

    def valid_url?(url)
      uri = URI.parse(url)
      %w[http https].include?(uri.scheme)
    rescue URI::InvalidURIError
      false
    end
  end
end
