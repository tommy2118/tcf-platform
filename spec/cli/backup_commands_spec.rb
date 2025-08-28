# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/cli/backup_commands'
require_relative '../../lib/backup_manager'
require_relative '../../lib/recovery_manager'

RSpec.describe TcfPlatform::BackupCommands do
  let(:cli) { Class.new { include TcfPlatform::BackupCommands }.new }
  let(:backup_manager) { instance_double(TcfPlatform::BackupManager) }
  let(:recovery_manager) { instance_double(TcfPlatform::RecoveryManager) }
  let(:config) { instance_double(TcfPlatform::Config) }

  before do
    allow(cli).to receive(:backup_manager).and_return(backup_manager)
    allow(cli).to receive(:recovery_manager).and_return(recovery_manager)
    allow(cli).to receive(:config).and_return(config)
  end

  describe '#backup_create' do
    let(:backup_id) { 'manual_backup_001' }
    let(:backup_result) do
      {
        backup_id: backup_id,
        status: 'completed',
        size: 1048576,
        duration: 45.2,
        components: {
          'databases' => { status: 'completed', count: 5 },
          'redis' => { status: 'completed', size: 524288 },
          'qdrant' => { status: 'completed', size: 2097152 },
          'repositories' => { status: 'completed', count: 6 },
          'configuration' => { status: 'completed', size: 262144 }
        }
      }
    end

    it 'creates new backup with progress indication' do
      allow(backup_manager).to receive(:create_backup).with(backup_id, incremental: false).and_return(backup_result)

      output = capture_stdout { cli.backup_create(backup_id) }

      expect(output).to include(
        "Creating backup: #{backup_id}",
        'Discovering data sources...',
        '✅ Databases: 5 databases backed up',
        '✅ Redis: Data exported',
        '✅ Repositories: 6 repositories archived',
        'Backup completed successfully'
      )
    end

    it 'supports incremental backup creation' do
      allow(backup_manager).to receive(:create_backup).with(backup_id, incremental: true).and_return(
        backup_result.merge(type: 'incremental', base_backup: 'backup_20240827_120000')
      )

      output = capture_stdout { cli.backup_create(backup_id, incremental: true) }

      expect(output).to include(
        'Creating incremental backup',
        'Base backup: backup_20240827_120000'
      )
    end

    it 'handles backup failures gracefully' do
      failed_result = backup_result.merge(
        status: 'partial',
        components: backup_result[:components].merge(
          'databases' => { status: 'failed', error: 'Connection timeout' }
        )
      )
      allow(backup_manager).to receive(:create_backup).and_return(failed_result)

      output = capture_stdout { cli.backup_create(backup_id) }

      expect(output).to include(
        '❌ Databases: Connection timeout',
        'Backup completed with errors'
      )
    end

    it 'shows size information in human readable format' do
      allow(backup_manager).to receive(:create_backup).and_return(backup_result)

      output = capture_stdout { cli.backup_create(backup_id) }

      expect(output).to include('Total size: 1.0 MB')
      expect(output).to include('Duration: 45.2 seconds')
    end
  end

  describe '#backup_list' do
    let(:sample_backups) do
      [
        {
          backup_id: 'backup_20240827_120000',
          created_at: Time.parse('2024-08-27 12:00:00'),
          size: 1048576,
          type: 'full',
          status: 'completed'
        },
        {
          backup_id: 'backup_20240826_180000',
          created_at: Time.parse('2024-08-26 18:00:00'),
          size: 524288,
          type: 'incremental',
          status: 'completed'
        }
      ]
    end

    it 'displays available backups in table format' do
      allow(recovery_manager).to receive(:list_available_backups).with(from: nil, to: nil).and_return(sample_backups)

      output = capture_stdout { cli.backup_list }

      expect(output).to include('Available Backups')
      expect(output).to include('backup_20240827_120000')
      expect(output).to include('backup_20240826_180000')
      expect(output).to include('full')
      expect(output).to include('incremental')
      expect(output).to include('1.0 MB')
      expect(output).to include('512.0 KB')
    end

    it 'supports date range filtering' do
      from_date = Date.parse('2024-08-27')
      to_date = Date.parse('2024-08-27')
      filtered_backups = [sample_backups.first]
      
      allow(recovery_manager).to receive(:list_available_backups)
        .with(from: from_date, to: to_date)
        .and_return(filtered_backups)

      output = capture_stdout { cli.backup_list(from: '2024-08-27', to: '2024-08-27') }

      expect(output).to include('backup_20240827_120000')
      expect(output).to_not include('backup_20240826_180000')
    end

    it 'shows message when no backups available' do
      allow(recovery_manager).to receive(:list_available_backups).and_return([])

      output = capture_stdout { cli.backup_list }

      expect(output).to include('No backups found')
    end
  end

  describe '#backup_restore' do
    let(:backup_id) { 'backup_20240827_120000' }
    let(:restore_result) do
      {
        backup_id: backup_id,
        status: 'completed',
        duration: 62.4,
        recovery_point: 'recovery_point_20240827_140000',
        components_restored: {
          'databases' => { status: 'restored', count: 5 },
          'redis' => { status: 'restored' },
          'repositories' => { status: 'restored', count: 6 }
        }
      }
    end

    it 'restores backup with confirmation and progress' do
      allow(cli).to receive(:yes?).with(/Are you sure you want to restore/).and_return(true)
      allow(recovery_manager).to receive(:restore_backup).with(backup_id, components: nil).and_return(restore_result)

      output = capture_stdout { cli.backup_restore(backup_id) }

      expect(output).to include(
        "Restoring backup: #{backup_id}",
        '✅ Recovery point created: recovery_point_20240827_140000',
        '✅ Databases: 5 databases restored',
        '✅ Redis: Data restored',
        '✅ Repositories: 6 repositories restored',
        'Restoration completed successfully'
      )
    end

    it 'supports selective component restoration' do
      components = ['databases', 'redis']
      allow(cli).to receive(:yes?).and_return(true)
      allow(recovery_manager).to receive(:restore_backup).with(backup_id, components: components).and_return(
        restore_result.merge(components_restored: restore_result[:components_restored].select { |k, _| components.include?(k) })
      )

      output = capture_stdout { cli.backup_restore(backup_id, components: components.join(',')) }

      expect(output).to include('Restoring components: databases, redis')
      expect(output).to include('✅ Databases: 5 databases restored')
      expect(output).to include('✅ Redis: Data restored')
      expect(output).to_not include('repositories')
    end

    it 'aborts when user declines confirmation' do
      allow(cli).to receive(:yes?).and_return(false)
      allow(recovery_manager).to receive(:restore_backup)  # Create stub for verification

      output = capture_stdout { cli.backup_restore(backup_id) }

      expect(output).to include('Restoration cancelled')
      expect(recovery_manager).not_to have_received(:restore_backup)
    end

    it 'handles restoration failures gracefully' do
      allow(cli).to receive(:yes?).and_return(true)
      failed_result = restore_result.merge(
        status: 'partial',
        components_restored: restore_result[:components_restored].merge(
          'databases' => { status: 'failed', error: 'Database connection failed' }
        )
      )
      allow(recovery_manager).to receive(:restore_backup).and_return(failed_result)

      output = capture_stdout { cli.backup_restore(backup_id) }

      expect(output).to include('❌ Databases: Database connection failed')
      expect(output).to include('Restoration completed with errors')
    end
  end

  describe '#backup_validate' do
    let(:backup_id) { 'backup_20240827_120000' }

    it 'validates backup and shows detailed results' do
      validation_result = {
        backup_id: backup_id,
        valid: true,
        errors: [],
        checks: {
          files_exist: true,
          checksums_valid: true,
          metadata_valid: true
        }
      }
      allow(recovery_manager).to receive(:validate_backup).with(backup_id).and_return(validation_result)

      output = capture_stdout { cli.backup_validate(backup_id) }

      expect(output).to include(
        "Validating backup: #{backup_id}",
        '✅ Files exist: All backup files present',
        '✅ Checksums: All files verified',
        '✅ Metadata: Backup metadata valid',
        'Backup validation passed'
      )
    end

    it 'reports validation failures with details' do
      validation_result = {
        backup_id: backup_id,
        valid: false,
        errors: ['Checksum mismatch in databases component', 'Missing configuration files'],
        checks: {
          files_exist: false,
          checksums_valid: false,
          metadata_valid: true
        }
      }
      allow(recovery_manager).to receive(:validate_backup).and_return(validation_result)

      output = capture_stdout { cli.backup_validate(backup_id) }

      expect(output).to include(
        '❌ Files exist: Missing backup files',
        '❌ Checksums: Verification failed',
        '✅ Metadata: Backup metadata valid',
        'Backup validation failed',
        'Checksum mismatch in databases component',
        'Missing configuration files'
      )
    end
  end

  describe '#backup_status' do
    it 'shows backup system status and statistics' do
      allow(backup_manager).to receive(:discover_backup_sources).and_return({
        databases: { 'tcf_personas' => { size: 1048576 } },
        redis: { size: 524288 },
        repositories: { 'tcf-gateway' => { size: 262144 } }
      })
      allow(backup_manager).to receive(:estimated_backup_size).and_return(1835008)
      allow(recovery_manager).to receive(:list_available_backups).and_return([
        { backup_id: 'backup_1', status: 'completed', size: 1048576 },
        { backup_id: 'backup_2', status: 'completed', size: 524288 }
      ])

      output = capture_stdout { cli.backup_status }

      expect(output).to include(
        'Backup System Status',
        'Data Sources:',
        'Databases: 1 database (1.0 MB)',
        'Redis: 512.0 KB',
        'Repositories: 1 repository (256.0 KB)',
        'Estimated backup size: 1.8 MB',
        'Available backups: 2',
        'Total backup storage: 1.5 MB'
      )
    end
  end

  # Helper method to capture stdout
  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end
end