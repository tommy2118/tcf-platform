# frozen_string_literal: true

require_relative '../config_manager'
require_relative '../config_validator'
require_relative '../security_manager'
require_relative 'config_help_commands'
require_relative 'config_generation_commands'
require_relative 'config_validation_commands'
require_relative 'config_display_commands'
require_relative 'config_management_commands'

module TcfPlatform
  class CLI < Thor
    # Configuration management commands for TCF Platform
    # Refactored into focused, modular command groups for better maintainability
    module ConfigCommands
      def self.included(base)
        base.class_eval do
          # Include all configuration command modules
          include ConfigHelpCommands
          include ConfigGenerationCommands
          include ConfigValidationCommands
          include ConfigDisplayCommands
          include ConfigManagementCommands
        end
      end
    end
  end
end
