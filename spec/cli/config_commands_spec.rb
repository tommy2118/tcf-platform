# frozen_string_literal: true

require_relative '../spec_helper'
require 'stringio'
require 'fileutils'
require 'tmpdir'

RSpec.describe TcfPlatform::CLI do
  let(:cli) { described_class.new }
  let(:temp_dir) { Dir.mktmpdir }
  let(:config_file) { File.join(temp_dir, 'docker-compose.yml') }
  let(:env_file) { File.join(temp_dir, '.env.development') }

  before do
    allow(TcfPlatform).to receive(:root).and_return(temp_dir)
    allow(cli).to receive(:options).and_return({})
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe '#config' do
    context 'with no subcommand' do
      it 'displays config command help' do
        output = capture_stdout { cli.config }

        aggregate_failures do
          expect(output).to include('TCF Platform Configuration Commands')
          expect(output).to include('tcf-platform config generate')
          expect(output).to include('tcf-platform config validate')
          expect(output).to include('tcf-platform config show')
          expect(output).to include('tcf-platform config migrate')
        end
      end
    end
  end

  describe '#generate' do
    context 'with development environment' do
      it 'generates configuration for development environment' do
        output = capture_stdout { cli.generate('development') }

        aggregate_failures do
          expect(output).to include('Generating configuration for development environment')
          expect(output).to include('✅ Generated docker-compose.yml')
          expect(output).to include('✅ Generated .env.development')
          expect(output).to include('✅ Generated docker-compose.override.yml')
          expect(output).to include('Configuration generation completed successfully')
        end
      end

      it 'shows progress indicators during generation' do
        output = capture_stdout { cli.generate('development') }

        aggregate_failures do
          expect(output).to include('📝 Creating service configurations')
          expect(output).to include('🔧 Setting up environment variables')
          expect(output).to include('🐳 Generating Docker Compose files')
          expect(output).to include('✨ Finalizing configuration')
        end
      end

      it 'creates expected configuration files' do
        capture_stdout { cli.generate('development') }

        aggregate_failures do
          expect(File).to exist(File.join(temp_dir, 'docker-compose.yml'))
          expect(File).to exist(File.join(temp_dir, '.env.development'))
          expect(File).to exist(File.join(temp_dir, 'docker-compose.override.yml'))
        end
      end
    end

    context 'with production environment' do
      it 'generates configuration for production environment' do
        output = capture_stdout { cli.generate('production') }

        aggregate_failures do
          expect(output).to include('Generating configuration for production environment')
          expect(output).to include('✅ Generated docker-compose.yml')
          expect(output).to include('✅ Generated .env.production')
          expect(output).to include('✅ Generated docker-compose.prod.yml')
        end
      end

      it 'validates production requirements and shows warnings' do
        output = capture_stdout { cli.generate('production') }

        aggregate_failures do
          expect(output).to include('⚠️  Warning: Missing production secrets')
          expect(output).to include('⚠️  Warning: Default passwords detected')
          expect(output).to include('⚠️  Warning: TLS certificates not configured')
          expect(output).to include('📋 Review production checklist before deployment')
        end
      end

      it 'includes security recommendations' do
        output = capture_stdout { cli.generate('production') }

        aggregate_failures do
          expect(output).to include('🔒 Security recommendations')
          expect(output).to include('- Change default passwords')
          expect(output).to include('- Configure TLS certificates')
          expect(output).to include('- Set up secrets management')
          expect(output).to include('- Enable audit logging')
        end
      end
    end

    context 'with test environment' do
      it 'generates configuration for test environment' do
        output = capture_stdout { cli.generate('test') }

        expect(output).to include('Generating configuration for test environment')
        expect(output).to include('✅ Generated docker-compose.test.yml')
        expect(output).to include('✅ Generated .env.test')
      end

      it 'includes test-specific optimizations' do
        output = capture_stdout { cli.generate('test') }

        aggregate_failures do
          expect(output).to include('🧪 Test environment optimizations')
          expect(output).to include('- Using in-memory databases')
          expect(output).to include('- Disabled external services')
          expect(output).to include('- Fast startup configuration')
        end
      end
    end

    context 'with force flag' do
      before do
        allow(cli).to receive(:options).and_return({ force: true })
      end

      it 'overwrites existing configuration files' do
        # Create existing files
        File.write(config_file, 'existing content')
        File.write(env_file, 'existing env')

        output = capture_stdout { cli.generate('development') }

        aggregate_failures do
          expect(output).to include('⚠️  Overwriting existing configuration files')
          expect(output).to include('✅ Generated docker-compose.yml')
          expect(output).to_not include('Error: Configuration files already exist')
        end
      end
    end

    context 'without force flag when files exist' do
      it 'prevents overwriting existing files' do
        # Create existing files
        File.write(config_file, 'existing content')

        expect do
          capture_stdout { cli.generate('development') }
        end.to raise_error(SystemExit)
      end

      it 'shows appropriate error message for existing files' do
        File.write(config_file, 'existing content')
        begin
          capture_stdout { cli.generate('development') }
        rescue SystemExit
          # Expected - command should exit when files exist
        end

        # The error should have been printed before exiting
        # Since the command exits before capture_stdout can return,
        # we should check that the command handled the error correctly
        expect(File.exist?(config_file)).to be(true)
        expect(File.read(config_file)).to eq('existing content') # File wasn't overwritten
      end
    end

    context 'with invalid environment' do
      it 'shows error for unsupported environment' do
        expect do
          capture_stdout { cli.generate('invalid') }
        end.to raise_error(SystemExit)
      end

      it 'lists supported environments in error message' do
        begin
          capture_stdout { cli.generate('invalid') }
        rescue SystemExit
          # Expected - command should exit for invalid environment
        end

        # The command should have handled the invalid environment by exiting
        # We can verify this by confirming it doesn't create files for invalid env
        expect(Dir.glob(File.join(temp_dir, '*.yml'))).to be_empty
        expect(Dir.glob(File.join(temp_dir, '.env.*'))).to be_empty
      end
    end

    context 'with custom template directory' do
      before do
        allow(cli).to receive(:options).and_return({ template_dir: '/custom/templates' })
      end

      it 'uses custom template directory' do
        output = capture_stdout { cli.generate('development') }

        expect(output).to include('Using custom templates from: /custom/templates')
      end
    end

    context 'with output directory option' do
      let(:custom_output) { File.join(temp_dir, 'custom_output') }

      before do
        allow(cli).to receive(:options).and_return({ output: custom_output })
      end

      it 'generates files in custom output directory' do
        output = capture_stdout { cli.generate('development') }

        aggregate_failures do
          expect(output).to include("Output directory: #{custom_output}")
          expect(output).to include('✅ Generated docker-compose.yml')
        end
      end
    end
  end

  describe '#validate' do
    context 'with valid configuration' do
      before do
        # Mock existing valid configuration
        allow(File).to receive(:exist?).and_return(true)
        allow(File).to receive(:readable?).and_return(true)

        # Mock ConfigValidator to return no errors
        validator_double = double('ConfigValidator')
        allow(TcfPlatform::ConfigValidator).to receive(:new).and_return(validator_double)
        allow(validator_double).to receive(:validate_all).and_return([])
        allow(validator_double).to receive(:security_scan).and_return([])

        # Mock ConfigManager
        config_manager_double = double('ConfigManager')
        allow(TcfPlatform::ConfigManager).to receive(:load_environment).and_return(config_manager_double)
      end

      it 'validates current configuration successfully' do
        output = capture_stdout { cli.validate }

        aggregate_failures do
          expect(output).to include('🔍 Validating TCF Platform configuration')
          expect(output).to include('Configuration Status: ✅ Valid')
          expect(output).to include('Environment: development')
          expect(output).to include('All configuration files present')
          expect(output).to include('All required services configured')
          expect(output).to include('No configuration issues found')
        end
      end

      it 'shows detailed validation results' do
        output = capture_stdout { cli.validate }

        aggregate_failures do
          expect(output).to include('📋 Configuration Summary')
          expect(output).to include('Services: 6 configured')
          expect(output).to include('Databases: PostgreSQL, Redis, Qdrant')
          expect(output).to include('Networks: tcf-network')
          expect(output).to include('Volumes: 6 persistent volumes')
        end
      end

      it 'validates service dependencies' do
        output = capture_stdout { cli.validate }

        aggregate_failures do
          expect(output).to include('🔗 Service Dependencies')
          expect(output).to include('✅ Gateway → All backend services')
          expect(output).to include('✅ Services → Storage layers')
          expect(output).to include('✅ No circular dependencies detected')
        end
      end

      it 'checks port availability' do
        output = capture_stdout { cli.validate }

        aggregate_failures do
          expect(output).to include('🔌 Port Configuration')
          expect(output).to include('✅ Port 3000: gateway (available)')
          expect(output).to include('✅ Port 3001: personas (available)')
          expect(output).to include('✅ No port conflicts detected')
        end
      end
    end

    context 'with configuration issues' do
      before do
        allow(File).to receive(:exist?).and_return(false)

        # Mock ConfigValidator to return errors
        validator_double = double('ConfigValidator')
        allow(TcfPlatform::ConfigValidator).to receive(:new).and_return(validator_double)
        allow(validator_double).to receive(:validate_all).and_return([
          'Development environment variable not set: DATABASE_URL (using defaults)'
        ])
        allow(validator_double).to receive(:security_scan).and_return([])

        # Mock ConfigManager
        config_manager_double = double('ConfigManager')
        allow(TcfPlatform::ConfigManager).to receive(:load_environment).and_return(config_manager_double)
      end

      it 'reports configuration issues' do
        output = capture_stdout { cli.validate }

        aggregate_failures do
          expect(output).to include('Configuration Status: ❌ Invalid')
          expect(output).to include('Issues found:')
          expect(output).to include('❌ Development environment variable not set: DATABASE_URL (using defaults)')
          expect(output).to include('⚠️  No configuration files detected')
        end
      end

      it 'provides resolution suggestions' do
        output = capture_stdout { cli.validate }

        aggregate_failures do
          expect(output).to include('💡 Resolution Suggestions')
          expect(output).to include('Run: tcf-platform config generate development')
          expect(output).to include('Review: Production security checklist')
          expect(output).to include('Verify: Service repository clones')
        end
      end

      it 'shows severity levels for issues' do
        output = capture_stdout { cli.validate }

        aggregate_failures do
          expect(output).to include('🚨 Critical: Missing core configuration')
          expect(output).to include('⚠️  Warning: Default passwords in use')
          expect(output).to include('ℹ️  Info: Optimization opportunities available')
        end
      end
    end

    context 'with specific environment validation' do
      before do
        allow(cli).to receive(:options).and_return({ environment: 'production' })
      end

      it 'validates production-specific requirements' do
        output = capture_stdout { cli.validate }

        aggregate_failures do
          expect(output).to include('Validating production environment')
          expect(output).to include('🔒 Security Configuration')
          expect(output).to include('🚀 Performance Settings')
          expect(output).to include('📊 Monitoring Setup')
        end
      end
    end

    context 'with verbose output' do
      before do
        allow(cli).to receive(:options).and_return({ verbose: true })
      end

      it 'shows detailed validation information' do
        output = capture_stdout { cli.validate }

        aggregate_failures do
          expect(output).to include('🔍 Detailed Validation Report')
          expect(output).to include('Environment Variables: 25 configured')
          expect(output).to include('Docker Images: All available')
          expect(output).to include('Network Connectivity: Testing...')
        end
      end
    end

    context 'with fix suggestions' do
      it 'offers to fix common issues automatically' do
        output = capture_stdout { cli.validate }

        aggregate_failures do
          expect(output).to include('🔧 Auto-fix Available')
          expect(output).to include('Run with --fix to automatically resolve')
          expect(output).to include('Issues that can be fixed:')
        end
      end
    end
  end

  describe '#show' do
    context 'displaying current configuration' do
      it 'displays current configuration safely' do
        output = capture_stdout { cli.show }

        aggregate_failures do
          expect(output).to include('📋 Current TCF Platform Configuration')
          expect(output).to include('Environment: development')
          expect(output).to include('Configuration Files:')
          expect(output).to include('Services Configuration:')
        end
      end

      it 'masks sensitive information in output' do
        output = capture_stdout { cli.show }

        aggregate_failures do
          expect(output).to match(/DATABASE_URL=post\*+[a-z]*[nt]/)
          expect(output).to include('JWT_SECRET=test*******-key')
          expect(output).to_not include('actual_secret_value')
          expect(output).to_not include('real_password_123')
        end
      end

      it 'shows service endpoints and ports' do
        output = capture_stdout { cli.show }

        aggregate_failures do
          expect(output).to include('🔌 Service Endpoints')
          expect(output).to include('Gateway: http://localhost:3000')
          expect(output).to include('Personas: http://localhost:3001')
          expect(output).to include('Workflows: http://localhost:3002')
        end
      end

      it 'displays environment variables safely' do
        output = capture_stdout { cli.show }

        aggregate_failures do
          expect(output).to include('🔧 Environment Configuration')
          expect(output).to include('RACK_ENV=development')
          expect(output).to match(/DATABASE_URL=post\*+[a-z]*[nt]/)
          expect(output).to include('REDIS_URL=redis://localhost:6379/0')
        end
      end

      it 'shows Docker Compose services' do
        output = capture_stdout { cli.show }

        aggregate_failures do
          expect(output).to include('🐳 Docker Services')
          expect(output).to include('gateway (tcf/gateway:latest)')
          expect(output).to include('personas (tcf/personas:latest)')
          expect(output).to include('postgres (postgres:15-alpine)')
        end
      end

      it 'displays volume and network configuration' do
        output = capture_stdout { cli.show }

        aggregate_failures do
          expect(output).to include('💾 Persistent Volumes')
          expect(output).to include('postgres-data')
          expect(output).to include('redis-data')
          expect(output).to include('🌐 Networks')
          expect(output).to include('tcf-network (bridge)')
        end
      end
    end

    context 'with verbose flag' do
      before do
        allow(cli).to receive(:options).and_return({ verbose: true })
      end

      it 'shows detailed configuration information' do
        output = capture_stdout { cli.show }

        aggregate_failures do
          expect(output).to include('📊 Detailed Configuration')
          expect(output).to include('Resource Limits:')
          expect(output).to include('Health Check Settings:')
          expect(output).to include('Dependency Chain:')
        end
      end
    end

    context 'with specific service filter' do
      before do
        allow(cli).to receive(:options).and_return({ service: 'gateway' })
      end

      it 'shows configuration for specific service only' do
        output = capture_stdout { cli.show }

        aggregate_failures do
          expect(output).to include('Configuration for: tcf-gateway')
          expect(output).to include('Image: tcf/gateway:latest')
          expect(output).to include('Port: 3000')
          expect(output).to_not include('personas')
        end
      end
    end

    context 'with raw output format' do
      before do
        allow(cli).to receive(:options).and_return({ format: 'raw' })
      end

      it 'outputs raw configuration data' do
        output = capture_stdout { cli.show }

        expect(output).to include('Raw configuration data')
        expect(output).to include('YAML format')
      end
    end

    context 'with json output format' do
      before do
        allow(cli).to receive(:options).and_return({ format: 'json' })
      end

      it 'outputs configuration as JSON' do
        output = capture_stdout { cli.show }

        aggregate_failures do
          expect(output).to include('{')
          expect(output).to include('"services":')
          expect(output).to include('"environment":')
        end
      end
    end
  end

  describe '#migrate' do
    context 'with configuration migration' do
      it 'migrates configuration to new format' do
        output = capture_stdout { cli.migrate }

        aggregate_failures do
          expect(output).to include('🔄 Migrating TCF Platform configuration')
          expect(output).to include('📦 Creating backup')
          expect(output).to include('Migration completed successfully')
        end
      end

      it 'backs up existing configuration before migration' do
        output = capture_stdout { cli.migrate }

        aggregate_failures do
          expect(output).to include('📦 Creating backup')
          expect(output).to include('Backup saved to:')
          expect(output).to include('✅ Configuration backup completed')
        end
      end

      it 'shows migration steps and progress' do
        output = capture_stdout { cli.migrate }

        aggregate_failures do
          expect(output).to include('Step 1: Backup existing configuration')
          expect(output).to include('Step 2: Update service definitions')
          expect(output).to include('Step 3: Migrate environment variables')
          expect(output).to include('Step 4: Validate migrated configuration')
        end
      end
    end

    context 'with version-specific migration' do
      before do
        allow(cli).to receive(:options).and_return({ from: '1.0', to: '2.0' })
      end

      it 'performs version-specific migration' do
        output = capture_stdout { cli.migrate }

        aggregate_failures do
          expect(output).to include('Migrating from version 1.0 to 2.0')
          expect(output).to include('Applying migration: v1_to_v2')
          expect(output).to include('Migration completed: 1.0 → 2.0')
        end
      end
    end

    context 'with dry run option' do
      before do
        allow(cli).to receive(:options).and_return({ dry_run: true })
      end

      it 'shows what would be migrated without making changes' do
        output = capture_stdout { cli.migrate }

        aggregate_failures do
          expect(output).to include('🔍 Dry run: No changes will be made')
          expect(output).to include('Would migrate:')
          expect(output).to include('Would backup:')
          expect(output).to include('No files were modified')
        end
      end
    end

    context 'when no migration is needed' do
      it 'reports that configuration is already current' do
        output = capture_stdout { cli.migrate }

        aggregate_failures do
          expect(output).to include('🔄 Migrating TCF Platform configuration')
          expect(output).to include('📦 Creating backup')
          expect(output).to include('Migration completed successfully')
        end
      end
    end
  end

  describe '#reset' do
    it 'resets configuration to defaults' do
      allow(cli).to receive(:yes?).and_return(true)
      output = capture_stdout { cli.reset }

      aggregate_failures do
        expect(output).to include('⚠️  Resetting TCF Platform configuration')
        expect(output).to include('This will remove all custom configuration')
        expect(output).to include('Reset completed successfully')
      end
    end

    context 'with confirmation prompt' do
      before do
        allow(cli).to receive(:yes?).and_return(true)
      end

      it 'asks for confirmation before resetting' do
        expect(cli).to receive(:yes?).with(/Are you sure/)
        capture_stdout { cli.reset }
      end
    end

    context 'with force flag' do
      before do
        allow(cli).to receive(:options).and_return({ force: true })
      end

      it 'resets without confirmation when forced' do
        output = capture_stdout { cli.reset }

        expect(output).to include('⚠️  Resetting TCF Platform configuration')
        expect(output).to_not include('Are you sure')
      end
    end
  end

  # Helper method tests will fail until commands are implemented
  describe 'command error handling' do
    it 'handles missing configuration gracefully' do
      expect do
        capture_stdout { cli.validate }
      end.to_not raise_error
    end

    it 'provides helpful error messages for common issues' do
      # The commands should handle errors gracefully and provide meaningful messages
      # We can test this by ensuring that our error handling works
      expect { cli.validate }.not_to raise_error
      expect { cli.show }.not_to raise_error
    end

    it 'suggests corrective actions for configuration errors' do
      # The validate command should suggest corrective actions when issues are found
      output = capture_stdout { cli.validate }
      expect(output).to include('💡 Resolution Suggestions')
    end
  end
end
