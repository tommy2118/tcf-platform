# frozen_string_literal: true

module TcfPlatform
  class CLI < Thor
    # Configuration help and documentation commands
    module ConfigHelpCommands
      def self.included(base)
        base.class_eval do
          desc 'config', 'Display configuration commands help'
          def config
            display_config_commands_header
            display_available_commands
            display_command_examples
          end

          private

          def display_config_commands_header
            puts 'TCF Platform Configuration Commands'
            puts '=' * 40
            puts ''
          end

          def display_available_commands
            puts 'Available Commands:'
            display_command_list
            puts ''
          end

          def display_command_list
            commands = [
              ['generate <env>', 'Generate configuration for environment'],
              ['validate', 'Validate current configuration'],
              ['show', 'Display current configuration'],
              ['migrate', 'Migrate configuration between versions'],
              ['reset', 'Reset configuration to defaults']
            ]

            commands.each do |command, description|
              puts "  tcf-platform config #{command.ljust(25)} # #{description}"
            end
          end

          def display_command_examples
            puts 'Examples:'
            display_example_commands
            puts ''
          end

          def display_example_commands
            examples = [
              'tcf-platform config generate development',
              'tcf-platform config generate production',
              'tcf-platform config validate --environment production',
              'tcf-platform config show --service gateway',
              'tcf-platform config migrate --from 1.0 --to 2.0',
              'tcf-platform config reset --force'
            ]

            examples.each { |example| puts "  #{example}" }
          end
        end
      end
    end
  end
end
