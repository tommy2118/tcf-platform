# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/dev_environment'
require_relative '../../lib/system_checker'

RSpec.describe TcfPlatform::DevEnvironment do
  let(:dev_environment) { described_class.new }

  describe '#setup' do
    it 'validates system prerequisites before setup' do
      expect(dev_environment).to respond_to(:setup)
      
      result = dev_environment.setup
      
      aggregate_failures do
        expect(result).to be_a(Hash)
        expect(result[:status]).to eq('success')
        expect(result[:steps_completed]).to be_an(Array)
        expect(result[:prerequisites_validated]).to be(true)
      end
    end

    it 'sets up development environment with all required services' do
      result = dev_environment.setup
      
      aggregate_failures do
        expect(result[:steps_completed]).to include('docker_check')
        expect(result[:steps_completed]).to include('repositories_cloned')
        expect(result[:steps_completed]).to include('services_configured')
        expect(result[:environment_ready]).to be(true)
      end
    end

    it 'handles setup failures gracefully' do
      allow_any_instance_of(TcfPlatform::SystemChecker).to receive(:docker_available?).and_return(false)
      
      result = dev_environment.setup
      
      aggregate_failures do
        expect(result[:status]).to eq('error')
        expect(result[:error]).to include('Docker')
        expect(result[:prerequisites_validated]).to be(false)
      end
    end
  end

  describe '#validate' do
    it 'validates all development environment components' do
      expect(dev_environment).to respond_to(:validate)
      
      result = dev_environment.validate
      
      aggregate_failures do
        expect(result).to be_a(Hash)
        expect(result).to have_key(:valid)
        expect(result).to have_key(:checks)
        expect(result[:checks]).to be_an(Array)
      end
    end

    it 'performs comprehensive system validation checks' do
      result = dev_environment.validate
      
      expected_checks = %w[docker repositories database redis services]
      
      aggregate_failures do
        check_names = result[:checks].map { |check| check[:name] }
        expected_checks.each do |check_name|
          expect(check_names).to include(check_name)
        end
      end
    end

    it 'reports validation status for each component' do
      result = dev_environment.validate
      
      result[:checks].each do |check|
        aggregate_failures do
          expect(check).to have_key(:name)
          expect(check).to have_key(:status)
          expect(check).to have_key(:message)
          expect(%w[pass fail warning]).to include(check[:status])
        end
      end
    end
  end

  describe '#status' do
    it 'returns current development environment status' do
      expect(dev_environment).to respond_to(:status)
      
      result = dev_environment.status
      
      aggregate_failures do
        expect(result).to be_a(Hash)
        expect(result).to have_key(:environment_ready)
        expect(result).to have_key(:services_status)
        expect(result).to have_key(:last_validation)
      end
    end
  end
end

RSpec.describe TcfPlatform::SystemChecker do
  let(:system_checker) { described_class.new }

  describe '#docker_available?' do
    it 'checks if Docker is installed and running' do
      expect(system_checker).to respond_to(:docker_available?)
      expect(system_checker.docker_available?).to be_in([true, false])
    end
  end

  describe '#docker_compose_available?' do
    it 'checks if Docker Compose is available' do
      expect(system_checker).to respond_to(:docker_compose_available?)
      expect(system_checker.docker_compose_available?).to be_in([true, false])
    end
  end

  describe '#prerequisites_met?' do
    it 'validates all system prerequisites' do
      expect(system_checker).to respond_to(:prerequisites_met?)
      
      result = system_checker.prerequisites_met?
      
      aggregate_failures do
        expect(result).to be_a(Hash)
        expect(result).to have_key(:met)
        expect(result).to have_key(:checks)
        expect(result[:checks]).to be_an(Array)
      end
    end
  end

  describe '#check_ports' do
    it 'verifies required ports are available' do
      expect(system_checker).to respond_to(:check_ports)
      
      ports = [3000, 3001, 3002, 3003, 3004, 3005]
      result = system_checker.check_ports(ports)
      
      aggregate_failures do
        expect(result).to be_a(Hash)
        expect(result).to have_key(:available)
        expect(result).to have_key(:blocked_ports)
        expect(result[:blocked_ports]).to be_an(Array)
      end
    end
  end
end