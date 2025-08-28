# frozen_string_literal: true

require 'spec_helper'
require 'tcf_platform'
require_relative '../../lib/docker_manager'

RSpec.describe TcfPlatform::DockerManager do
  subject(:docker_manager) { described_class.new }

  describe '#running_services' do
    it 'detects running TCF services' do
      # Mock docker-compose ps to return a running tcf-gateway service
      allow(docker_manager).to receive(:docker_compose_ps).and_return([
        { name: 'tcf-gateway', state: 'running', health: 'healthy' }
      ])
      expect(docker_manager.running_services).to include('tcf-gateway')
    end

    it 'returns empty array when no services running' do
      allow(docker_manager).to receive(:docker_compose_ps).and_return([])
      expect(docker_manager.running_services).to eq([])
    end
  end

  describe '#service_status' do
    it 'returns detailed status for each service' do
      # Mock docker-compose ps to return service info
      allow(docker_manager).to receive(:docker_compose_ps).and_return([
        { name: 'tcf-gateway', state: 'running', health: 'healthy' }
      ])
      status = docker_manager.service_status
      expect(status).to have_key('tcf-gateway')
      expect(status['tcf-gateway']).to include(:status, :health, :port)
    end

    it 'handles services that are not running' do
      allow(docker_manager).to receive(:docker_compose_ps).and_return([])
      status = docker_manager.service_status
      expect(status).to be_a(Hash)
      expect(status['tcf-gateway']).to include(:status, :health, :port)
      expect(status['tcf-gateway'][:status]).to eq('not_running')
    end
  end

  describe '#compose_file_exists?' do
    it 'returns true when docker-compose.yml exists' do
      expect(docker_manager.compose_file_exists?).to be_truthy
    end
  end
end