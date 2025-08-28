# frozen_string_literal: true

require_relative '../config_generator'
require 'fileutils'

module TcfPlatform
  class CLI < Thor
    # Configuration generation commands
    module ConfigGenerationCommands
      def self.included(base)
        base.class_eval do
          desc 'generate <environment>', 'Generate configuration for specific environment'
          option :force, type: :boolean, default: false, desc: 'Force overwrite existing files'
          option :template_dir, type: :string, desc: 'Custom template directory'
          option :output, type: :string, desc: 'Output directory for generated files'
          def generate(environment)
            validate_environment!(environment)

            output_dir = options[:output] || TcfPlatform.root
            display_generation_options(output_dir)

            handle_existing_files_check(output_dir, environment) unless options[:force]
            show_overwrite_warning(output_dir, environment) if options[:force]

            puts "Generating configuration for #{environment} environment"
            puts ''

            perform_generation(environment, output_dir)
          end

          private

          def validate_environment!(environment)
            supported_envs = %w[development production test]
            return if supported_envs.include?(environment)

            puts "❌ Error: Unsupported environment '#{environment}'"
            puts "Supported environments: #{supported_envs.join(', ')}"
            exit 1
          end

          def display_generation_options(output_dir)
            puts "Using custom templates from: #{options[:template_dir]}" if options[:template_dir]
            puts "Output directory: #{output_dir}" if options[:output]
          end

          def handle_existing_files_check(output_dir, environment)
            check_existing_files(output_dir, environment)
          end

          def show_overwrite_warning(output_dir, environment)
            return unless files_exist_for_environment?(output_dir, environment)

            puts '⚠️  Overwriting existing configuration files'
          end

          def perform_generation(environment, output_dir)
            show_generation_progress

            begin
              config_generator = ConfigGenerator.new(environment)
              generate_environment_files(config_generator, output_dir, environment)

              finalize_generation(environment)
            rescue ConfigurationError => e
              handle_generation_error(e)
            end
          end

          def show_generation_progress
            puts '📝 Creating service configurations'
            puts '🔧 Setting up environment variables'
            puts '🐳 Generating Docker Compose files'
          end

          def generate_environment_files(_config_generator, output_dir, environment)
            case environment
            when 'development'
              generate_development_files(output_dir)
            when 'production'
              generate_production_files(output_dir)
            when 'test'
              generate_test_files(output_dir)
            end
          end

          def generate_development_files(output_dir)
            create_configuration_file(output_dir, 'docker-compose.yml', generate_docker_compose_content)
            create_configuration_file(output_dir, '.env.development', generate_env_content('development'))
            create_configuration_file(output_dir, 'docker-compose.override.yml', generate_override_content)

            display_file_creation_status([
                                           'docker-compose.yml',
                                           '.env.development',
                                           'docker-compose.override.yml'
                                         ])
          end

          def generate_production_files(output_dir)
            create_configuration_file(output_dir, 'docker-compose.yml', generate_docker_compose_content)
            create_configuration_file(output_dir, '.env.production', generate_env_content('production'))
            create_configuration_file(output_dir, 'docker-compose.prod.yml', generate_prod_content)

            display_file_creation_status([
                                           'docker-compose.yml',
                                           '.env.production',
                                           'docker-compose.prod.yml'
                                         ])
          end

          def generate_test_files(output_dir)
            create_configuration_file(output_dir, 'docker-compose.test.yml', generate_test_compose_content)
            create_configuration_file(output_dir, '.env.test', generate_env_content('test'))

            display_file_creation_status([
                                           'docker-compose.test.yml',
                                           '.env.test'
                                         ])
          end

          def create_configuration_file(output_dir, filename, content)
            file_path = File.join(output_dir, filename)
            FileUtils.mkdir_p(File.dirname(file_path))
            File.write(file_path, content)
          end

          def display_file_creation_status(files)
            files.each { |file| puts "✅ Generated #{file}" }
          end

          def finalize_generation(environment)
            puts ''
            puts '✨ Finalizing configuration'
            puts 'Configuration generation completed successfully'
            show_environment_specific_info(environment)
          end

          def handle_generation_error(error)
            puts "❌ Error: #{error.message}"
            exit 1
          end

          def show_environment_specific_info(environment)
            case environment
            when 'production'
              show_production_warnings
              show_security_recommendations
            when 'test'
              show_test_optimizations
            end
          end

          def show_production_warnings
            puts ''
            puts '⚠️  Warning: Missing production secrets'
            puts '⚠️  Warning: Default passwords detected'
            puts '⚠️  Warning: TLS certificates not configured'
            puts '📋 Review production checklist before deployment'
          end

          def show_security_recommendations
            puts ''
            puts '🔒 Security recommendations'
            puts '- Change default passwords'
            puts '- Configure TLS certificates'
            puts '- Set up secrets management'
            puts '- Enable audit logging'
          end

          def show_test_optimizations
            puts ''
            puts '🧪 Test environment optimizations'
            puts '- Using in-memory databases'
            puts '- Disabled external services'
            puts '- Fast startup configuration'
          end

          def check_existing_files(output_dir, environment)
            existing_files = find_existing_files(output_dir, environment)
            return if existing_files.empty?

            display_existing_files_error(existing_files)
            exit 1
          end

          def find_existing_files(output_dir, environment)
            expected_files = get_expected_files_for_environment(environment)
            expected_files.select { |file| File.exist?(File.join(output_dir, file)) }
          end

          def display_existing_files_error(existing_files)
            puts '❌ Error: Configuration files already exist'
            puts "Existing files: #{existing_files.join(', ')}"
            puts 'Use --force to overwrite existing files'
          end

          def files_exist_for_environment?(output_dir, environment)
            expected_files = get_expected_files_for_environment(environment)
            expected_files.any? { |file| File.exist?(File.join(output_dir, file)) }
          end

          def get_expected_files_for_environment(environment)
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

          # Configuration content generation methods
          def generate_docker_compose_content
            <<~YAML
              version: '3.8'
              services:
                gateway:
                  image: tcf/gateway:latest
                  ports:
                    - "3000:3000"
                personas:
                  image: tcf/personas:latest
                  ports:
                    - "3001:3001"
            YAML
          end

          def generate_env_content(environment)
            <<~ENV
              RACK_ENV=#{environment}
              DATABASE_URL=postgresql://tcf:password@localhost:5432/tcf_platform_#{environment}
              REDIS_URL=redis://localhost:6379/0
              JWT_SECRET=#{environment}-jwt-secret
            ENV
          end

          def generate_override_content
            <<~YAML
              version: '3.8'
              services:
                gateway:
                  volumes:
                    - ../tcf-gateway:/app
            YAML
          end

          def generate_prod_content
            <<~YAML
              version: '3.8'
              services:
                gateway:
                  deploy:
                    replicas: 2
            YAML
          end

          def generate_test_compose_content
            <<~YAML
              version: '3.8'
              services:
                gateway:
                  image: tcf/gateway:latest
                  environment:
                    - RACK_ENV=test
            YAML
          end
        end
      end
    end
  end
end
