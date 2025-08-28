# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/backup_manager'

RSpec.describe TcfPlatform::BackupManager do
  let(:config) { instance_double(TcfPlatform::Config) }
  let(:docker_manager) { instance_double(TcfPlatform::DockerManager) }
  let(:backup_manager) { described_class.new(config, docker_manager) }

  before do
    allow(config).to receive(:repository_config).and_return({
      'tcf-gateway' => { 'url' => 'git@github.com:tommy2118/tcf-gateway.git' },
      'tcf-personas' => { 'url' => 'git@github.com:tommy2118/tcf-personas.git' }
    })
    allow(docker_manager).to receive(:service_status).and_return({
      'postgres' => { status: 'running' },
      'redis' => { status: 'running' },
      'qdrant' => { status: 'running' }
    })
  end

  describe '#discover_backup_sources' do
    it 'identifies all data sources requiring backup' do
      allow(backup_manager).to receive(:calculate_database_size).and_return(100)
      allow(backup_manager).to receive(:calculate_redis_size).and_return(50)
      allow(backup_manager).to receive(:calculate_qdrant_size).and_return(75)
      allow(backup_manager).to receive(:calculate_repository_size).and_return(25)
      allow(backup_manager).to receive(:calculate_configuration_size).and_return(10)

      sources = backup_manager.discover_backup_sources

      expect(sources).to include(
        databases: hash_including(
          'tcf_personas' => hash_including(type: 'postgresql', size: be_a(Integer)),
          'tcf_workflows' => hash_including(type: 'postgresql', size: be_a(Integer)),
          'tcf_projects' => hash_including(type: 'postgresql', size: be_a(Integer)),
          'tcf_context' => hash_including(type: 'postgresql', size: be_a(Integer)),
          'tcf_tokens' => hash_including(type: 'postgresql', size: be_a(Integer))
        ),
        redis: hash_including(type: 'redis', size: be_a(Integer)),
        qdrant: hash_including(type: 'qdrant', size: be_a(Integer)),
        repositories: hash_including(
          'tcf-gateway' => hash_including(type: 'git', size: be_a(Integer)),
          'tcf-personas' => hash_including(type: 'git', size: be_a(Integer))
        ),
        configuration: hash_including(type: 'files', size: be_a(Integer))
      )
    end

    it 'calculates backup size estimates' do
      allow(backup_manager).to receive(:calculate_database_size).and_return(100)
      allow(backup_manager).to receive(:calculate_redis_size).and_return(50)
      allow(backup_manager).to receive(:calculate_qdrant_size).and_return(75)
      allow(backup_manager).to receive(:calculate_repository_size).and_return(25)
      allow(backup_manager).to receive(:calculate_configuration_size).and_return(10)

      sources = backup_manager.discover_backup_sources
      total_size = sources.values.map { |data| data.is_a?(Hash) && data[:size] ? data[:size] : data.values.sum { |item| item[:size] } }.sum

      expect(total_size).to be > 0
      expect(backup_manager.estimated_backup_size).to eq(total_size)
    end
  end

  describe '#create_backup' do
    let(:backup_id) { "backup_#{Time.now.strftime('%Y%m%d_%H%M%S')}" }

    it 'creates comprehensive backup of all data sources' do
      allow(backup_manager).to receive(:backup_databases).and_return(
        status: 'completed', count: 5, duration: 30.5
      )
      allow(backup_manager).to receive(:backup_redis).and_return(
        status: 'completed', size: 1024, duration: 5.2
      )
      allow(backup_manager).to receive(:backup_qdrant).and_return(
        status: 'completed', size: 2048, duration: 10.1
      )
      allow(backup_manager).to receive(:backup_repositories).and_return(
        status: 'completed', count: 6, duration: 15.3
      )
      allow(backup_manager).to receive(:backup_configuration).and_return(
        status: 'completed', size: 512, duration: 2.1
      )

      result = backup_manager.create_backup(backup_id)

      expect(result).to include(
        backup_id: backup_id,
        status: 'completed',
        size: be_a(Integer),
        duration: be_a(Float),
        components: hash_including(
          'databases' => hash_including(status: 'completed', count: 5),
          'redis' => hash_including(status: 'completed', size: be_a(Integer)),
          'repositories' => hash_including(status: 'completed', count: 6)
        )
      )
    end

    it 'handles backup failures gracefully' do
      allow(backup_manager).to receive(:backup_databases).and_raise(StandardError, 'Connection failed')
      allow(backup_manager).to receive(:backup_redis).and_return(status: 'completed', size: 1024, duration: 5.2)
      allow(backup_manager).to receive(:backup_qdrant).and_return(status: 'completed', size: 2048, duration: 10.1)
      allow(backup_manager).to receive(:backup_repositories).and_return(status: 'completed', count: 6, duration: 15.3)
      allow(backup_manager).to receive(:backup_configuration).and_return(status: 'completed', size: 512, duration: 2.1)

      result = backup_manager.create_backup('failed_backup')

      expect(result[:status]).to eq('partial')
      expect(result[:components]['databases'][:status]).to eq('failed')
      expect(result[:components]['databases'][:error]).to include('Connection failed')
    end

    it 'creates incremental backups when requested' do
      allow(backup_manager).to receive(:backup_databases).and_return(status: 'completed', count: 5, duration: 15.0, type: 'incremental')
      allow(backup_manager).to receive(:backup_redis).and_return(status: 'completed', size: 512, duration: 3.0, type: 'incremental')
      allow(backup_manager).to receive(:backup_qdrant).and_return(status: 'completed', size: 1024, duration: 5.0, type: 'incremental')
      allow(backup_manager).to receive(:backup_repositories).and_return(status: 'completed', count: 6, duration: 8.0, type: 'incremental')
      allow(backup_manager).to receive(:backup_configuration).and_return(status: 'completed', size: 256, duration: 1.0, type: 'incremental')
      allow(backup_manager).to receive(:find_last_backup).and_return('base_backup')

      # Create incremental backup
      result = backup_manager.create_backup('incremental_backup', incremental: true)

      expect(result[:type]).to eq('incremental')
      expect(result[:base_backup]).to eq('base_backup')
    end
  end
end