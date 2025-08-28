# frozen_string_literal: true

require 'spec_helper'
require 'tcf_platform'

RSpec.describe TcfPlatform::ConfigManager do
  let(:original_env) { ENV.to_h }

  before do
    # Clean environment for each test
    ENV.clear
    ENV.update(original_env)
    # Ensure spec_helper values are available for tests that need them
    ENV['JWT_SECRET'] ||= 'test-secret-key'
    ENV['REDIS_URL'] ||= 'redis://localhost:6379/0'
  end

  after do
    # Restore original environment
    ENV.clear
    ENV.update(original_env)
  end

  describe '.load_environment' do
    context 'when loading default development configuration' do
      it 'loads development configuration by default' do
        config = described_class.load_environment

        aggregate_failures do
          expect(config.environment).to eq('development')
          expect(config.database_url).to include('development')
          expect(config).to respond_to(:redis_url)
          expect(config).to respond_to(:jwt_secret)
        end
      end

      it 'provides sensible development defaults' do
        config = described_class.load_environment

        aggregate_failures do
          expect(config.redis_url).to eq('redis://localhost:6379/0')
          expect(config.database_url).to match(/postgresql.*development/)
          expect(config.jwt_secret).to be_present
        end
      end
    end

    context 'when loading specified environment configuration' do
      it 'loads production environment configuration' do
        ENV['RACK_ENV'] = 'production'
        ENV['DATABASE_URL'] = 'postgresql://prod:password@prod-db:5432/tcf_production'
        ENV['REDIS_URL'] = 'redis://prod-redis:6379/0'
        ENV['JWT_SECRET'] = 'super-secure-production-secret'

        config = described_class.load_environment('production')

        aggregate_failures do
          expect(config.environment).to eq('production')
          expect(config.database_url).to include('production')
          expect(config.redis_url).to include('prod-redis')
          expect(config.jwt_secret).to eq('super-secure-production-secret')
        end
      end

      it 'loads test environment configuration' do
        config = described_class.load_environment('test')

        aggregate_failures do
          expect(config.environment).to eq('test')
          expect(config.database_url).to include('test')
        end
      end
    end

    context 'when validating required environment variables' do
      it 'validates required production environment variables' do
        ENV['RACK_ENV'] = 'production'
        # Deliberately missing required variables
        ENV.delete('DATABASE_URL')
        ENV.delete('JWT_SECRET')

        expect do
          described_class.load_environment('production')
        end.to raise_error(TcfPlatform::ConfigurationError, /Missing required environment variables/)
      end

      it 'allows missing non-critical variables in development' do
        ENV['RACK_ENV'] = 'development'
        ENV.delete('OPENAI_API_KEY')
        ENV.delete('ANTHROPIC_API_KEY')

        expect do
          described_class.load_environment('development')
        end.not_to raise_error
      end

      it 'provides helpful error messages for missing required variables' do
        ENV['RACK_ENV'] = 'production'
        ENV.delete('DATABASE_URL')
        ENV.delete('JWT_SECRET')
        ENV.delete('REDIS_URL')

        expect do
          described_class.load_environment('production')
        end.to raise_error(TcfPlatform::ConfigurationError) do |error|
          aggregate_failures do
            expect(error.message).to include('DATABASE_URL')
            expect(error.message).to include('JWT_SECRET')
            expect(error.message).to include('REDIS_URL')
          end
        end
      end
    end

    context 'when handling environment file loading' do
      it 'loads configuration from .env files' do
        # This test assumes .env file loading capability
        config = described_class.load_environment
        expect(config).to respond_to(:from_env_file?)
      end

      it 'prioritizes environment variables over .env file values' do
        ENV['JWT_SECRET'] = 'env-override-secret'
        config = described_class.load_environment
        expect(config.jwt_secret).to eq('env-override-secret')
      end
    end
  end

  describe '#service_config' do
    let(:config) { described_class.load_environment }

    context 'when getting gateway service configuration' do
      it 'returns service-specific configuration for tcf-gateway' do
        gateway_config = config.service_config('tcf-gateway')

        aggregate_failures do
          expect(gateway_config).to be_a(Hash)
          expect(gateway_config[:port]).to eq(3000)
          expect(gateway_config[:environment]).to be_a(Hash)
          expect(gateway_config[:environment]).to include('JWT_SECRET')
          expect(gateway_config[:environment]).to include('REDIS_URL')
        end
      end

      it 'includes service discovery URLs in gateway config' do
        gateway_config = config.service_config('tcf-gateway')

        aggregate_failures do
          expect(gateway_config[:environment]).to include('TCF_PERSONAS_URL')
          expect(gateway_config[:environment]).to include('TCF_WORKFLOWS_URL')
          expect(gateway_config[:environment]).to include('TCF_PROJECTS_URL')
          expect(gateway_config[:environment]).to include('TCF_CONTEXT_URL')
          expect(gateway_config[:environment]).to include('TCF_TOKENS_URL')
        end
      end
    end

    context 'when getting microservice configurations' do
      it 'returns service-specific configuration for tcf-personas' do
        personas_config = config.service_config('tcf-personas')

        aggregate_failures do
          expect(personas_config[:port]).to eq(3001)
          expect(personas_config[:environment]).to include('DATABASE_URL')
          expect(personas_config[:environment]).to include('REDIS_URL')
          expect(personas_config[:environment]['DATABASE_URL']).to include('tcf_personas')
          expect(personas_config[:environment]['REDIS_URL']).to include('/1') # Redis DB 1
        end
      end

      it 'returns service-specific configuration for tcf-workflows' do
        workflows_config = config.service_config('tcf-workflows')

        aggregate_failures do
          expect(workflows_config[:port]).to eq(3002)
          expect(workflows_config[:environment]['DATABASE_URL']).to include('tcf_workflows')
          expect(workflows_config[:environment]['REDIS_URL']).to include('/2') # Redis DB 2
        end
      end

      it 'returns service-specific configuration for tcf-context' do
        context_config = config.service_config('tcf-context')

        aggregate_failures do
          expect(context_config[:port]).to eq(3004)
          expect(context_config[:environment]).to include('QDRANT_URL')
          expect(context_config[:environment]).to include('OPENAI_API_KEY')
        end
      end
    end

    context 'when handling unknown services' do
      it 'raises error for unknown service' do
        expect do
          config.service_config('unknown-service')
        end.to raise_error(TcfPlatform::ConfigurationError, /Unknown service: unknown-service/)
      end

      it 'provides list of available services in error message' do
        expect do
          config.service_config('invalid')
        end.to raise_error(TcfPlatform::ConfigurationError, /Available services:/)
      end
    end
  end

  describe '#docker_compose_config' do
    let(:config) { described_class.load_environment }

    it 'generates docker-compose environment configuration' do
      docker_config = config.docker_compose_config

      aggregate_failures do
        expect(docker_config).to be_a(Hash)
        expect(docker_config).to have_key('services')
        expect(docker_config['services']).to have_key('tcf-gateway')
        expect(docker_config['services']).to have_key('tcf-personas')
      end
    end

    it 'includes proper service networking configuration' do
      docker_config = config.docker_compose_config
      gateway_service = docker_config['services']['tcf-gateway']

      aggregate_failures do
        expect(gateway_service).to have_key('environment')
        expect(gateway_service).to have_key('depends_on')
        expect(gateway_service['depends_on']).to include('redis')
      end
    end

    it 'configures service-specific database URLs' do
      docker_config = config.docker_compose_config

      aggregate_failures do
        personas_env = docker_config['services']['tcf-personas']['environment']
        workflows_env = docker_config['services']['tcf-workflows']['environment']

        expect(personas_env['DATABASE_URL']).to include('tcf_personas')
        expect(workflows_env['DATABASE_URL']).to include('tcf_workflows')
      end
    end
  end

  describe '#validate!' do
    context 'when configuration is valid' do
      it 'does not raise error for valid development configuration' do
        config = described_class.load_environment('development')
        expect { config.validate! }.not_to raise_error
      end
    end

    context 'when configuration is invalid' do
      it 'raises error for missing required production variables' do
        ENV['RACK_ENV'] = 'production'
        ENV.delete('DATABASE_URL')

        config = described_class.load_environment('production')
        expect { config.validate! }.to raise_error(TcfPlatform::ConfigurationError)
      end

      it 'raises error for invalid database URLs' do
        ENV['DATABASE_URL'] = 'invalid-url'

        config = described_class.load_environment
        expect { config.validate! }.to raise_error(TcfPlatform::ConfigurationError, /Invalid DATABASE_URL/)
      end

      it 'raises error for invalid Redis URLs' do
        ENV['REDIS_URL'] = 'invalid-redis-url'

        config = described_class.load_environment
        expect { config.validate! }.to raise_error(TcfPlatform::ConfigurationError, /Invalid REDIS_URL/)
      end
    end
  end

  describe '#reload!' do
    it 'reloads configuration from environment' do
      config = described_class.load_environment
      original_secret = config.jwt_secret

      ENV['JWT_SECRET'] = 'new-secret-value'
      config.reload!

      expect(config.jwt_secret).to eq('new-secret-value')
      expect(config.jwt_secret).not_to eq(original_secret)
    end
  end
end
