# frozen_string_literal: true

module TcfPlatform
  # Base configuration exception class
  class ConfigurationError < StandardError
    attr_reader :context, :suggestions

    def initialize(message, context: nil, suggestions: [])
      super(message)
      @context = context || {}
      @suggestions = suggestions
    end

    def detailed_message
      msg = message
      msg += "\nContext: #{context}" if context.any?
      msg += "\nSuggestions:\n#{suggestions.map { |s| "  - #{s}" }.join("\n")}" if suggestions.any?
      msg
    end
  end

  # Specific exception types for different configuration errors
  class ValidationError < ConfigurationError; end
  class SecurityError < ConfigurationError; end
  class FileSystemError < ConfigurationError; end
  class EnvironmentError < ConfigurationError; end
  class NetworkError < ConfigurationError; end
  class ServiceConfigurationError < ConfigurationError; end

  # Exception helper module
  module ConfigurationExceptions
    def self.validation_error(message, field: nil, value: nil)
      context = {}
      context[:field] = field if field
      context[:value] = value if value && !SecurityManager.appears_sensitive?(field.to_s)

      suggestions = []
      suggestions << "Check the #{field} configuration" if field
      suggestions << 'Run validation with --verbose for more details'
      suggestions << 'Refer to the configuration documentation'

      ValidationError.new(message, context: context, suggestions: suggestions)
    end

    def self.security_error(message, type: nil, location: nil)
      context = {}
      context[:security_type] = type if type
      context[:location] = location if location

      suggestions = []
      case type
      when 'weak_password'
        suggestions << 'Use a stronger password (minimum 16 characters)'
        suggestions << 'Include uppercase, lowercase, numbers, and special characters'
      when 'missing_secret'
        suggestions << 'Set the required environment variable'
        suggestions << 'Use a secure secrets management system'
      when 'insecure_config'
        suggestions << 'Review security configuration'
        suggestions << 'Disable debug mode in production'
      end

      SecurityError.new(message, context: context, suggestions: suggestions)
    end

    def self.filesystem_error(message, path: nil, operation: nil)
      context = {}
      context[:path] = path if path
      context[:operation] = operation if operation

      suggestions = []
      suggestions << "Check if the path exists: #{path}" if path
      suggestions << "Verify file permissions for: #{path}" if path
      suggestions << 'Ensure the directory is writable' if operation == 'write'
      suggestions << 'Check available disk space' if operation == 'write'

      FileSystemError.new(message, context: context, suggestions: suggestions)
    end

    def self.environment_error(message, environment: nil, missing_vars: [])
      context = {}
      context[:environment] = environment if environment
      context[:missing_variables] = missing_vars if missing_vars.any?

      suggestions = []
      if missing_vars.any?
        suggestions << "Set the following environment variables: #{missing_vars.join(', ')}"
        suggestions << 'Create an appropriate .env file'
        suggestions << 'Check your environment configuration'
      end
      if environment
        suggestions << "Switch to a supported environment: #{ConfigGenerator::SUPPORTED_ENVIRONMENTS.join(', ')}"
      end

      EnvironmentError.new(message, context: context, suggestions: suggestions)
    end

    def self.network_error(message, url: nil, port: nil, service: nil)
      context = {}
      context[:url] = url if url
      context[:port] = port if port
      context[:service] = service if service

      suggestions = []
      suggestions << "Verify the service is running: #{service}" if service
      suggestions << "Check network connectivity to: #{url}" if url
      suggestions << "Ensure port #{port} is available" if port
      suggestions << 'Check firewall settings'
      suggestions << 'Verify DNS resolution'

      NetworkError.new(message, context: context, suggestions: suggestions)
    end

    def self.service_configuration_error(message, service: nil, config_type: nil)
      context = {}
      context[:service] = service if service
      context[:config_type] = config_type if config_type

      suggestions = []
      suggestions << "Review #{service} service configuration" if service
      suggestions << "Check #{config_type} settings" if config_type
      suggestions << 'Verify service dependencies'
      suggestions << 'Check service-specific environment variables'

      ServiceConfigurationError.new(message, context: context, suggestions: suggestions)
    end
  end
end
