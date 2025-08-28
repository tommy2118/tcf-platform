# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/backup_manager'
require_relative '../../lib/recovery_manager'

RSpec.describe TcfPlatform::RecoveryManager do
  let(:backup_manager) { instance_double(TcfPlatform::BackupManager) }
  let(:config) { instance_double(TcfPlatform::Config) }
  let(:docker_manager) { instance_double(TcfPlatform::DockerManager) }
  let(:recovery_manager) { described_class.new(backup_manager, config, docker_manager) }

  describe '#list_available_backups' do
    let(:sample_backups) do
      [
        {
          backup_id: 'backup_20240827_120000',
          created_at: Time.parse('2024-08-27 12:00:00'),
          size: 1024000,
          type: 'full',
          status: 'completed',
          components: { 'databases' => 5, 'redis' => 1, 'repositories' => 6 }
        },
        {
          backup_id: 'backup_20240826_120000',
          created_at: Time.parse('2024-08-26 12:00:00'),
          size: 512000,
          type: 'incremental',
          status: 'completed',
          components: { 'databases' => 5, 'redis' => 1 }
        }
      ]
    end

    it 'lists all available backups with metadata' do
      allow(backup_manager).to receive(:list_backups).and_return(sample_backups)

      backups = recovery_manager.list_available_backups

      expect(backups).to be_an(Array)
      expect(backups.size).to eq(2)
      expect(backups.first).to include(
        backup_id: be_a(String),
        created_at: be_a(Time),
        size: be_a(Integer),
        type: be_a(String),
        status: 'completed',
        components: be_a(Hash)
      )
    end

    it 'filters backups by date range' do
      allow(backup_manager).to receive(:list_backups).and_return(sample_backups)
      from_date = Date.parse('2024-08-27')
      to_date = Date.parse('2024-08-27')

      backups = recovery_manager.list_available_backups(from: from_date, to: to_date)

      expect(backups.size).to eq(1)
      expect(backups.first[:backup_id]).to eq('backup_20240827_120000')
    end

    it 'returns empty array when no backups match date range' do
      allow(backup_manager).to receive(:list_backups).and_return(sample_backups)
      from_date = Date.parse('2024-08-30')
      to_date = Date.parse('2024-08-30')

      backups = recovery_manager.list_available_backups(from: from_date, to: to_date)

      expect(backups).to be_empty
    end
  end

  describe '#restore_backup' do
    let(:backup_id) { 'backup_20240827_120000' }
    let(:backup_metadata) do
      {
        backup_id: backup_id,
        created_at: Time.parse('2024-08-27 12:00:00'),
        components: {
          'databases' => { status: 'completed', count: 5 },
          'redis' => { status: 'completed', size: 1024 },
          'qdrant' => { status: 'completed', size: 2048 },
          'repositories' => { status: 'completed', count: 6 },
          'configuration' => { status: 'completed', size: 512 }
        }
      }
    end

    before do
      allow(recovery_manager).to receive(:load_backup_metadata).with(backup_id).and_return(backup_metadata)
      allow(recovery_manager).to receive(:validate_backup_integrity).with(backup_id).and_return({ valid: true, errors: [] })
    end

    it 'restores complete platform from backup' do
      allow(recovery_manager).to receive(:create_recovery_point).and_return('recovery_point_20240827_140000')
      allow(recovery_manager).to receive(:restore_databases).and_return({ status: 'restored', count: 5, duration: 45.2 })
      allow(recovery_manager).to receive(:restore_redis).and_return({ status: 'restored', duration: 8.1 })
      allow(recovery_manager).to receive(:restore_qdrant).and_return({ status: 'restored', duration: 12.3 })
      allow(recovery_manager).to receive(:restore_repositories).and_return({ status: 'restored', count: 6, duration: 20.1 })
      allow(recovery_manager).to receive(:restore_configuration).and_return({ status: 'restored', duration: 3.2 })

      result = recovery_manager.restore_backup(backup_id)

      expect(result).to include(
        backup_id: backup_id,
        status: 'completed',
        components_restored: hash_including(
          'databases' => hash_including(status: 'restored', count: 5),
          'redis' => hash_including(status: 'restored'),
          'repositories' => hash_including(status: 'restored', count: 6)
        ),
        duration: be_a(Float)
      )
    end

    it 'supports selective component restoration' do
      components = ['databases', 'redis']
      allow(recovery_manager).to receive(:create_recovery_point).and_return('recovery_point_20240827_140000')
      allow(recovery_manager).to receive(:restore_databases).and_return({ status: 'restored', count: 5, duration: 45.2 })
      allow(recovery_manager).to receive(:restore_redis).and_return({ status: 'restored', duration: 8.1 })

      result = recovery_manager.restore_backup(backup_id, components: components)

      expect(result[:components_restored].keys).to match_array(components)
      expect(result[:components_restored]).to_not have_key('repositories')
      expect(result[:components_restored]).to_not have_key('qdrant')
      expect(result[:components_restored]).to_not have_key('configuration')
    end

    it 'validates backup integrity before restoration' do
      corrupted_backup_id = 'corrupted_backup'
      allow(recovery_manager).to receive(:load_backup_metadata).with(corrupted_backup_id).and_return(backup_metadata)
      allow(recovery_manager).to receive(:validate_backup_integrity).with(corrupted_backup_id).and_return(
        valid: false, 
        errors: ['Checksum mismatch in databases component']
      )

      expect {
        recovery_manager.restore_backup(corrupted_backup_id)
      }.to raise_error(TcfPlatform::BackupCorruptedError, /Checksum mismatch/)
    end

    it 'creates recovery point before restoration' do
      expect(recovery_manager).to receive(:create_recovery_point).and_return('recovery_point_20240827_140000')
      allow(recovery_manager).to receive(:restore_databases).and_return({ status: 'restored', count: 5, duration: 45.2 })
      allow(recovery_manager).to receive(:restore_redis).and_return({ status: 'restored', duration: 8.1 })
      allow(recovery_manager).to receive(:restore_qdrant).and_return({ status: 'restored', duration: 12.3 })
      allow(recovery_manager).to receive(:restore_repositories).and_return({ status: 'restored', count: 6, duration: 20.1 })
      allow(recovery_manager).to receive(:restore_configuration).and_return({ status: 'restored', duration: 3.2 })

      result = recovery_manager.restore_backup(backup_id)

      expect(result[:recovery_point]).to eq('recovery_point_20240827_140000')
    end

    it 'handles restoration failures gracefully' do
      allow(recovery_manager).to receive(:create_recovery_point).and_return('recovery_point_20240827_140000')
      allow(recovery_manager).to receive(:restore_databases).and_raise(StandardError, 'Database connection failed')
      allow(recovery_manager).to receive(:restore_redis).and_return({ status: 'restored', duration: 8.1 })
      allow(recovery_manager).to receive(:restore_qdrant).and_return({ status: 'restored', duration: 12.3 })
      allow(recovery_manager).to receive(:restore_repositories).and_return({ status: 'restored', count: 6, duration: 20.1 })
      allow(recovery_manager).to receive(:restore_configuration).and_return({ status: 'restored', duration: 3.2 })

      result = recovery_manager.restore_backup(backup_id)

      expect(result[:status]).to eq('partial')
      expect(result[:components_restored]['databases'][:status]).to eq('failed')
      expect(result[:components_restored]['databases'][:error]).to include('Database connection failed')
    end
  end

  describe '#validate_backup' do
    let(:backup_id) { 'backup_20240827_120000' }

    it 'validates backup integrity and returns validation results' do
      allow(recovery_manager).to receive(:check_backup_files_exist).with(backup_id).and_return(true)
      allow(recovery_manager).to receive(:verify_backup_checksums).with(backup_id).and_return({ valid: true, errors: [] })
      allow(recovery_manager).to receive(:validate_backup_metadata).with(backup_id).and_return({ valid: true, errors: [] })

      result = recovery_manager.validate_backup(backup_id)

      expect(result).to include(
        backup_id: backup_id,
        valid: true,
        errors: be_empty,
        checks: hash_including(
          files_exist: true,
          checksums_valid: true,
          metadata_valid: true
        )
      )
    end

    it 'detects backup corruption and reports issues' do
      allow(recovery_manager).to receive(:check_backup_files_exist).with(backup_id).and_return(false)
      allow(recovery_manager).to receive(:verify_backup_checksums).with(backup_id).and_return({ 
        valid: false, 
        errors: ['Checksum mismatch in databases/tcf_personas.sql'] 
      })
      allow(recovery_manager).to receive(:validate_backup_metadata).with(backup_id).and_return({ valid: true, errors: [] })

      result = recovery_manager.validate_backup(backup_id)

      expect(result[:valid]).to be false
      expect(result[:errors]).to include(/Checksum mismatch/)
      expect(result[:checks][:files_exist]).to be false
      expect(result[:checks][:checksums_valid]).to be false
    end
  end
end