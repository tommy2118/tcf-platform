# frozen_string_literal: true

require 'spec_helper'
require 'tcf_platform'

RSpec.describe TcfPlatform::ConfigGenerator do
  let(:development_generator) { described_class.new('development') }
  let(:production_generator) { described_class.new('production') }
  let(:test_generator) { described_class.new('test') }

  describe '#initialize' do
    context 'when initialized with valid environment' do
      it 'creates generator for development environment' do
        generator = described_class.new('development')
        
        aggregate_failures do
          expect(generator.environment).to eq('development')
          expect(generator).to respond_to(:generate_compose_file)
          expect(generator).to respond_to(:generate_env_file)
        end
      end

      it 'creates generator for production environment' do
        generator = described_class.new('production')
        
        aggregate_failures do
          expect(generator.environment).to eq('production')
          expect(generator.template_path).to be_present
        end
      end

      it 'creates generator for test environment' do
        generator = described_class.new('test')
        
        expect(generator.environment).to eq('test')
      end
    end

    context 'when initialized with invalid environment' do
      it 'raises error for unsupported environment' do
        expect {
          described_class.new('invalid_env')
        }.to raise_error(TcfPlatform::ConfigurationError, /Unsupported environment: invalid_env/)
      end

      it 'raises error for nil environment' do
        expect {
          described_class.new(nil)
        }.to raise_error(TcfPlatform::ConfigurationError, /Environment cannot be nil/)
      end
    end
  end

  describe '#generate_compose_file' do
    context 'when generating development Docker Compose' do
      it 'generates Docker Compose with correct environment variables' do
        compose_content = development_generator.generate_compose_file
        
        aggregate_failures do
          expect(compose_content).to include('RACK_ENV=development')
          expect(compose_content).to include('DATABASE_URL=postgresql://tcf:password@postgres:5432/tcf_development')
          expect(compose_content).to include('REDIS_URL=redis://redis:6379/0')
        end
      end

      it 'includes all TCF services with correct ports' do
        compose_content = development_generator.generate_compose_file
        
        aggregate_failures do
          expect(compose_content).to include('tcf-gateway')
          expect(compose_content).to include('tcf-personas')
          expect(compose_content).to include('tcf-workflows')
          expect(compose_content).to include('tcf-projects')
          expect(compose_content).to include('tcf-context')
          expect(compose_content).to include('tcf-tokens')
          expect(compose_content).to include('ports:', '- "3000:3000"')
          expect(compose_content).to include('- "3001:3001"')
        end
      end

      it 'includes all service dependencies correctly' do
        compose_content = development_generator.generate_compose_file
        
        aggregate_failures do
          expect(compose_content).to include('depends_on:')
          expect(compose_content).to include('redis')
          expect(compose_content).to include('postgres')
          expect(compose_content).to include('qdrant')
        end
      end

      it 'configures service discovery URLs for gateway' do
        compose_content = development_generator.generate_compose_file
        
        aggregate_failures do
          expect(compose_content).to include('TCF_PERSONAS_URL=http://personas:3001')
          expect(compose_content).to include('TCF_WORKFLOWS_URL=http://workflows:3002')
          expect(compose_content).to include('TCF_CONTEXT_URL=http://context:3004')
          expect(compose_content).to include('TCF_TOKENS_URL=http://tokens:3005')
        end
      end

      it 'includes development-specific volume mounts' do
        compose_content = development_generator.generate_compose_file
        
        aggregate_failures do
          expect(compose_content).to include('volumes:')
          expect(compose_content).to include('~/.claude:/root/.claude:ro')
          expect(compose_content).to include('../tcf-gateway:/app')
        end
      end
    end

    context 'when generating production Docker Compose' do
      it 'generates production Docker Compose with security settings' do
        compose_content = production_generator.generate_compose_file
        
        aggregate_failures do
          expect(compose_content).to include('RACK_ENV=production')
          expect(compose_content).to include('restart: always')
          expect(compose_content).to include('deploy:')
          expect(compose_content).to include('replicas: 2')
        end
      end

      it 'uses production database URLs with environment variables' do
        compose_content = production_generator.generate_compose_file
        
        aggregate_failures do
          expect(compose_content).to include('DATABASE_URL=${POSTGRES_URL}')
          expect(compose_content).to include('REDIS_URL=${REDIS_URL}')
          expect(compose_content).to_not include('password@postgres')
        end
      end

      it 'includes resource limits for production services' do
        compose_content = production_generator.generate_compose_file
        
        aggregate_failures do
          expect(compose_content).to include('resources:')
          expect(compose_content).to include('limits:')
          expect(compose_content).to include('cpus:')
          expect(compose_content).to include('memory:')
        end
      end

      it 'configures production monitoring services' do
        compose_content = production_generator.generate_compose_file
        
        aggregate_failures do
          expect(compose_content).to include('prometheus:')
          expect(compose_content).to include('grafana:')
          expect(compose_content).to include('image: prom/prometheus:latest')
        end
      end
    end

    context 'when generating test Docker Compose' do
      it 'generates test environment with isolated databases' do
        compose_content = test_generator.generate_compose_file
        
        aggregate_failures do
          expect(compose_content).to include('RACK_ENV=test')
          expect(compose_content).to include('tcf_test')
          expect(compose_content).to include('redis://redis:6379/15')
        end
      end

      it 'excludes production-only services in test mode' do
        compose_content = test_generator.generate_compose_file
        
        aggregate_failures do
          expect(compose_content).to_not include('prometheus:')
          expect(compose_content).to_not include('grafana:')
          expect(compose_content).to_not include('deploy:')
        end
      end
    end

    context 'when handling template variables' do
      it 'substitutes all template variables correctly' do
        compose_content = development_generator.generate_compose_file
        
        aggregate_failures do
          expect(compose_content).to_not include('{{')
          expect(compose_content).to_not include('}}')
          expect(compose_content).to_not include('${UNDEFINED_VAR}')
        end
      end

      it 'raises error for missing required template variables' do
        allow(development_generator).to receive(:template_variables).and_return({})
        
        expect {
          development_generator.generate_compose_file
        }.to raise_error(TcfPlatform::ConfigurationError, /Missing template variables/)
      end
    end
  end

  describe '#generate_env_file' do
    context 'when generating development .env file' do
      it 'creates environment-specific .env file' do
        env_content = development_generator.generate_env_file
        
        aggregate_failures do
          expect(env_content).to include('POSTGRES_PASSWORD=development_password')
          expect(env_content).to include('REDIS_PASSWORD=development_redis_password')
          expect(env_content).to include('ENVIRONMENT=development')
        end
      end

      it 'includes development API key placeholders' do
        env_content = development_generator.generate_env_file
        
        aggregate_failures do
          expect(env_content).to include('OPENAI_API_KEY=your-openai-key-here')
          expect(env_content).to include('ANTHROPIC_API_KEY=your-anthropic-key-here')
          expect(env_content).to include('# Replace with actual keys for development')
        end
      end

      it 'does not include any real secrets' do
        env_content = development_generator.generate_env_file
        
        aggregate_failures do
          expect(env_content).to_not include('sk-')
          expect(env_content).to_not include('prod-')
          expect(env_content).to_not match(/[a-f0-9]{32}/)
        end
      end
    end

    context 'when generating production .env file' do
      it 'creates production .env template with placeholders' do
        env_content = production_generator.generate_env_file
        
        aggregate_failures do
          expect(env_content).to include('POSTGRES_PASSWORD=${SECURE_POSTGRES_PASSWORD}')
          expect(env_content).to include('JWT_SECRET=${SECURE_JWT_SECRET}')
          expect(env_content).to include('ENVIRONMENT=production')
        end
      end

      it 'includes security warnings for production secrets' do
        env_content = production_generator.generate_env_file
        
        aggregate_failures do
          expect(env_content).to include('# SECURITY WARNING')
          expect(env_content).to include('# Replace all placeholders with actual values')
          expect(env_content).to include('# Never commit production secrets')
        end
      end

      it 'includes production database configuration' do
        env_content = production_generator.generate_env_file
        
        aggregate_failures do
          expect(env_content).to include('POSTGRES_HOST=${DB_HOST}')
          expect(env_content).to include('POSTGRES_PORT=5432')
          expect(env_content).to include('POSTGRES_SSL=require')
        end
      end
    end

    context 'when generating test .env file' do
      it 'creates test-specific environment variables' do
        env_content = test_generator.generate_env_file
        
        aggregate_failures do
          expect(env_content).to include('POSTGRES_PASSWORD=test_password')
          expect(env_content).to include('ENVIRONMENT=test')
          expect(env_content).to include('TEST_DATABASE_CLEANER=true')
        end
      end

      it 'includes test-safe dummy values' do
        env_content = test_generator.generate_env_file
        
        aggregate_failures do
          expect(env_content).to include('OPENAI_API_KEY=test-key-openai')
          expect(env_content).to include('ANTHROPIC_API_KEY=test-key-anthropic')
          expect(env_content).to include('JWT_SECRET=test-jwt-secret')
        end
      end
    end
  end

  describe '#generate_nginx_config' do
    context 'when generating nginx configuration for production' do
      it 'creates nginx reverse proxy configuration' do
        nginx_config = production_generator.generate_nginx_config
        
        aggregate_failures do
          expect(nginx_config).to include('upstream tcf-gateway')
          expect(nginx_config).to include('server 127.0.0.1:3000')
          expect(nginx_config).to include('proxy_pass http://tcf-gateway')
        end
      end

      it 'includes SSL configuration for production' do
        nginx_config = production_generator.generate_nginx_config
        
        aggregate_failures do
          expect(nginx_config).to include('ssl_certificate')
          expect(nginx_config).to include('ssl_certificate_key')
          expect(nginx_config).to include('ssl_protocols TLSv1.2 TLSv1.3')
        end
      end

      it 'configures security headers' do
        nginx_config = production_generator.generate_nginx_config
        
        aggregate_failures do
          expect(nginx_config).to include('add_header X-Frame-Options DENY')
          expect(nginx_config).to include('add_header X-Content-Type-Options nosniff')
          expect(nginx_config).to include('add_header Strict-Transport-Security')
        end
      end
    end

    context 'when generating nginx configuration for development' do
      it 'creates simple proxy configuration without SSL' do
        nginx_config = development_generator.generate_nginx_config
        
        aggregate_failures do
          expect(nginx_config).to include('listen 80')
          expect(nginx_config).to_not include('ssl_certificate')
          expect(nginx_config).to_not include('https')
        end
      end
    end
  end

  describe '#generate_k8s_manifests' do
    context 'when generating Kubernetes manifests for production' do
      it 'creates deployment manifests for all services' do
        k8s_manifests = production_generator.generate_k8s_manifests
        
        aggregate_failures do
          expect(k8s_manifests).to include('apiVersion: apps/v1')
          expect(k8s_manifests).to include('kind: Deployment')
          expect(k8s_manifests).to include('name: tcf-gateway')
          expect(k8s_manifests).to include('replicas: 3')
        end
      end

      it 'creates service manifests for inter-service communication' do
        k8s_manifests = production_generator.generate_k8s_manifests
        
        aggregate_failures do
          expect(k8s_manifests).to include('kind: Service')
          expect(k8s_manifests).to include('port: 3000')
          expect(k8s_manifests).to include('targetPort: 3000')
        end
      end

      it 'includes persistent volume claims for data' do
        k8s_manifests = production_generator.generate_k8s_manifests
        
        aggregate_failures do
          expect(k8s_manifests).to include('kind: PersistentVolumeClaim')
          expect(k8s_manifests).to include('storage: 10Gi')
          expect(k8s_manifests).to include('ReadWriteOnce')
        end
      end
    end
  end

  describe '#template_variables' do
    it 'provides environment-specific template variables' do
      variables = development_generator.template_variables
      
      aggregate_failures do
        expect(variables).to be_a(Hash)
        expect(variables).to have_key(:environment)
        expect(variables).to have_key(:database_password)
        expect(variables[:environment]).to eq('development')
      end
    end

    it 'includes service URLs in template variables' do
      variables = development_generator.template_variables
      
      aggregate_failures do
        expect(variables).to have_key(:gateway_url)
        expect(variables).to have_key(:personas_url)
        expect(variables[:gateway_url]).to include('3000')
      end
    end

    it 'masks secrets in production template variables' do
      variables = production_generator.template_variables
      
      aggregate_failures do
        expect(variables[:database_password]).to include('${')
        expect(variables[:jwt_secret]).to include('${')
        expect(variables).to_not include_any_real_secrets
      end
    end
  end

  describe '#validate_templates' do
    it 'validates all template files exist' do
      expect {
        development_generator.validate_templates
      }.not_to raise_error
    end

    it 'raises error for missing template files' do
      allow(File).to receive(:exist?).and_return(false)
      
      expect {
        development_generator.validate_templates
      }.to raise_error(TcfPlatform::ConfigurationError, /Template file not found/)
    end

    it 'validates template syntax is correct' do
      # Mock File.read to return valid content for existence check but ERB.new to fail
      allow(File).to receive(:exist?).and_return(true)
      allow(File).to receive(:read).and_return('valid template content')
      
      # Mock ERB.new to raise an exception on the first call
      original_erb_new = ERB.method(:new)
      call_count = 0
      
      allow(ERB).to receive(:new) do |content|
        call_count += 1
        if call_count == 1
          raise StandardError, "Template syntax error"
        else
          original_erb_new.call(content)
        end
      end
      
      expect {
        development_generator.validate_templates  
      }.to raise_error(TcfPlatform::ConfigurationError, /Invalid template syntax/)
    end
  end

  describe '#write_configs' do
    let(:output_dir) { '/tmp/tcf-test-configs' }

    before do
      FileUtils.rm_rf(output_dir) if Dir.exist?(output_dir)
    end

    after do
      FileUtils.rm_rf(output_dir) if Dir.exist?(output_dir)
    end

    it 'writes all configuration files to specified directory' do
      development_generator.write_configs(output_dir)
      
      aggregate_failures do
        expect(File.exist?(File.join(output_dir, 'docker-compose.yml'))).to be true
        expect(File.exist?(File.join(output_dir, '.env'))).to be true
        expect(File.exist?(File.join(output_dir, 'nginx.conf'))).to be true
      end
    end

    it 'creates directory if it does not exist' do
      expect(Dir.exist?(output_dir)).to be false
      
      development_generator.write_configs(output_dir)
      
      expect(Dir.exist?(output_dir)).to be true
    end

    it 'overwrites existing files with confirmation' do
      # Create existing file
      FileUtils.mkdir_p(output_dir)
      File.write(File.join(output_dir, 'docker-compose.yml'), 'old content')
      
      development_generator.write_configs(output_dir, force: true)
      
      content = File.read(File.join(output_dir, 'docker-compose.yml'))
      expect(content).to_not eq('old content')
    end
  end

  # Custom matcher to check for secrets
  RSpec::Matchers.define :include_any_secrets do
    match do |actual|
      secret_patterns = [
        /sk-[a-zA-Z0-9]{48}/, # OpenAI API keys
        /sk-ant-[a-zA-Z0-9\-_]{95}/, # Anthropic API keys
        /AKIA[0-9A-Z]{16}/, # AWS Access Keys
        /[a-f0-9]{64}/ # Generic 64-char hex secrets
      ]
      
      secret_patterns.any? { |pattern| actual.match?(pattern) }
    end
    
    failure_message do |actual|
      "expected #{actual} to not contain any real secrets"
    end
  end

  RSpec::Matchers.define :include_any_real_secrets do
    match do |hash|
      return false unless hash.is_a?(Hash)
      
      hash.values.any? do |value|
        next false unless value.is_a?(String)
        
        # Check for real API key patterns
        value.match?(/sk-[a-zA-Z0-9]{48}/) || # OpenAI
        value.match?(/sk-ant-[a-zA-Z0-9\-_]{95}/) || # Anthropic  
        value.match?(/AKIA[0-9A-Z]{16}/) || # AWS
        value.match?(/[a-f0-9]{64}/) # Generic secrets
      end
    end
    
    failure_message do |actual|
      "expected template variables to not contain any real secrets, but found some"
    end
  end
end