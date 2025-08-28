# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'time'

module TcfPlatform
  # Manages backup operations for all TCF Platform data sources
  class BackupManager
    DATABASE_NAMES = %w[tcf_personas tcf_workflows tcf_projects tcf_context tcf_tokens].freeze

    def initialize(config, docker_manager, backup_path = './backups')
      @config = config
      @docker_manager = docker_manager
      @backup_path = backup_path
      ensure_backup_directory
    end

    def discover_backup_sources
      sources = {}

      # Database sources
      sources[:databases] = {}
      DATABASE_NAMES.each do |db_name|
        sources[:databases][db_name] = {
          type: 'postgresql',
          size: calculate_database_size(db_name)
        }
      end

      # Redis source
      sources[:redis] = {
        type: 'redis',
        size: calculate_redis_size
      }

      # Qdrant source
      sources[:qdrant] = {
        type: 'qdrant',
        size: calculate_qdrant_size
      }

      # Repository sources
      sources[:repositories] = {}
      @config.repository_config.each do |repo_name, _config|
        sources[:repositories][repo_name] = {
          type: 'git',
          size: calculate_repository_size(repo_name)
        }
      end

      # Configuration source
      sources[:configuration] = {
        type: 'files',
        size: calculate_configuration_size
      }

      sources
    end

    def estimated_backup_size
      sources = discover_backup_sources
      calculate_total_size(sources)
    end

    def create_backup(backup_id, incremental: false)
      start_time = Time.now
      result = {
        backup_id: backup_id,
        type: incremental ? 'incremental' : 'full',
        status: 'in_progress',
        components: {},
        created_at: start_time
      }

      if incremental
        result[:base_backup] = find_last_backup
      end

      backup_dir = File.join(@backup_path, backup_id)
      FileUtils.mkdir_p(backup_dir)

      # Backup each component
      component_results = backup_all_components(backup_dir, incremental)
      result[:components] = component_results

      # Calculate final status
      failed_components = component_results.select { |_, data| data[:status] == 'failed' }
      if failed_components.empty?
        result[:status] = 'completed'
      elsif failed_components.size == component_results.size
        result[:status] = 'failed'
      else
        result[:status] = 'partial'
      end

      # Calculate total size and duration
      result[:size] = calculate_backup_size(backup_dir)
      result[:duration] = Time.now - start_time

      # Save backup metadata
      save_backup_metadata(backup_id, result)

      result
    end

    def list_backups
      return [] unless Dir.exist?(@backup_path)

      Dir.glob(File.join(@backup_path, '*')).select { |path| File.directory?(path) }.map do |backup_dir|
        backup_id = File.basename(backup_dir)
        metadata_file = File.join(backup_dir, 'metadata.json')

        if File.exist?(metadata_file)
          JSON.parse(File.read(metadata_file), symbolize_names: true)
        else
          {
            backup_id: backup_id,
            created_at: File.ctime(backup_dir),
            status: 'unknown',
            size: calculate_backup_size(backup_dir)
          }
        end
      end.sort_by { |backup| backup[:created_at] }.reverse
    end

    def calculate_database_size(db_name = nil)
      # Simplified size calculation - would use actual database queries in real implementation
      1024 * 1024 # 1MB default
    end

    def calculate_redis_size
      # Simplified size calculation - would query Redis memory usage in real implementation
      512 * 1024 # 512KB default
    end

    def calculate_qdrant_size
      # Simplified size calculation - would query Qdrant storage in real implementation
      2048 * 1024 # 2MB default
    end

    def calculate_repository_size(repo_name = nil)
      # Simplified size calculation - would check actual repository size in real implementation
      1024 * 512 # 512KB default
    end

    def calculate_configuration_size
      # Simplified size calculation - would check actual config files in real implementation
      256 * 1024 # 256KB default
    end

    def backup_databases(backup_dir, incremental = false)
      start_time = Time.now
      databases_dir = File.join(backup_dir, 'databases')
      FileUtils.mkdir_p(databases_dir)

      begin
        DATABASE_NAMES.each do |db_name|
          dump_file = File.join(databases_dir, "#{db_name}.sql")
          # In real implementation, would use pg_dump
          File.write(dump_file, "-- Backup of #{db_name} database\n-- Created at #{Time.now}\n")
        end

        {
          status: 'completed',
          count: DATABASE_NAMES.size,
          duration: Time.now - start_time,
          type: incremental ? 'incremental' : 'full'
        }
      rescue StandardError => e
        {
          status: 'failed',
          error: e.message,
          duration: Time.now - start_time
        }
      end
    end

    def backup_redis(backup_dir, incremental = false)
      start_time = Time.now
      redis_file = File.join(backup_dir, 'redis.rdb')

      begin
        # In real implementation, would use Redis BGSAVE or SAVE
        File.write(redis_file, "Redis backup data placeholder\n")
        size = File.size(redis_file)

        {
          status: 'completed',
          size: size,
          duration: Time.now - start_time,
          type: incremental ? 'incremental' : 'full'
        }
      rescue StandardError => e
        {
          status: 'failed',
          error: e.message,
          duration: Time.now - start_time
        }
      end
    end

    def backup_qdrant(backup_dir, incremental = false)
      start_time = Time.now
      qdrant_dir = File.join(backup_dir, 'qdrant')
      FileUtils.mkdir_p(qdrant_dir)

      begin
        # In real implementation, would backup Qdrant storage
        File.write(File.join(qdrant_dir, 'collections.json'), "Qdrant backup data placeholder\n")
        size = calculate_backup_size(qdrant_dir)

        {
          status: 'completed',
          size: size,
          duration: Time.now - start_time,
          type: incremental ? 'incremental' : 'full'
        }
      rescue StandardError => e
        {
          status: 'failed',
          error: e.message,
          duration: Time.now - start_time
        }
      end
    end

    def backup_repositories(backup_dir, incremental = false)
      start_time = Time.now
      repos_dir = File.join(backup_dir, 'repositories')
      FileUtils.mkdir_p(repos_dir)

      begin
        @config.repository_config.each do |repo_name, _config|
          repo_backup_file = File.join(repos_dir, "#{repo_name}.tar.gz")
          # In real implementation, would create actual git archive
          File.write(repo_backup_file, "Repository #{repo_name} backup placeholder\n")
        end

        {
          status: 'completed',
          count: @config.repository_config.size,
          duration: Time.now - start_time,
          type: incremental ? 'incremental' : 'full'
        }
      rescue StandardError => e
        {
          status: 'failed',
          error: e.message,
          duration: Time.now - start_time
        }
      end
    end

    def backup_configuration(backup_dir, incremental = false)
      start_time = Time.now
      config_dir = File.join(backup_dir, 'configuration')
      FileUtils.mkdir_p(config_dir)

      begin
        # In real implementation, would backup actual configuration files
        File.write(File.join(config_dir, 'config.yml'), "Configuration backup placeholder\n")
        size = calculate_backup_size(config_dir)

        {
          status: 'completed',
          size: size,
          duration: Time.now - start_time,
          type: incremental ? 'incremental' : 'full'
        }
      rescue StandardError => e
        {
          status: 'failed',
          error: e.message,
          duration: Time.now - start_time
        }
      end
    end

    def find_last_backup
      backups = list_backups.select { |backup| backup[:status] == 'completed' && backup[:type] == 'full' }
      backups.first&.[](:backup_id) || 'base_backup'
    end

    private

    def ensure_backup_directory
      FileUtils.mkdir_p(@backup_path)
    end

    def calculate_total_size(sources)
      total = 0

      sources.each do |_category, data|
        if data.is_a?(Hash) && data[:size]
          total += data[:size]
        elsif data.is_a?(Hash)
          data.each { |_key, item| total += item[:size] if item.is_a?(Hash) && item[:size] }
        end
      end

      total
    end

    def backup_all_components(backup_dir, incremental)
      components = {}

      # Backup databases
      begin
        components['databases'] = backup_databases(backup_dir, incremental)
      rescue StandardError => e
        components['databases'] = { status: 'failed', error: e.message, duration: 0.0 }
      end

      # Backup Redis
      begin
        components['redis'] = backup_redis(backup_dir, incremental)
      rescue StandardError => e
        components['redis'] = { status: 'failed', error: e.message, duration: 0.0 }
      end

      # Backup Qdrant
      begin
        components['qdrant'] = backup_qdrant(backup_dir, incremental)
      rescue StandardError => e
        components['qdrant'] = { status: 'failed', error: e.message, duration: 0.0 }
      end

      # Backup repositories
      begin
        components['repositories'] = backup_repositories(backup_dir, incremental)
      rescue StandardError => e
        components['repositories'] = { status: 'failed', error: e.message, duration: 0.0 }
      end

      # Backup configuration
      begin
        components['configuration'] = backup_configuration(backup_dir, incremental)
      rescue StandardError => e
        components['configuration'] = { status: 'failed', error: e.message, duration: 0.0 }
      end

      components
    end

    def calculate_backup_size(backup_dir)
      return 0 unless Dir.exist?(backup_dir)

      size = 0
      Dir.glob(File.join(backup_dir, '**', '*')).each do |file|
        size += File.size(file) if File.file?(file)
      end
      size
    end

    def save_backup_metadata(backup_id, metadata)
      backup_dir = File.join(@backup_path, backup_id)
      metadata_file = File.join(backup_dir, 'metadata.json')

      File.write(metadata_file, JSON.pretty_generate(metadata))
    end
  end
end