# frozen_string_literal: true

require 'thor'
require_relative '../backup_manager'
require_relative '../recovery_manager'

module TcfPlatform
  # CLI commands for backup and recovery operations
  module BackupCommands
    def backup_create(backup_id, incremental: false)
      puts "Creating backup: #{backup_id}"
      puts 'Discovering data sources...'

      puts 'Creating incremental backup' if incremental

      result = backup_manager.create_backup(backup_id, incremental: incremental)

      puts "Base backup: #{result[:base_backup]}" if incremental && result[:base_backup]

      display_backup_progress(result)
      display_backup_summary(result)
    end

    def backup_list(from: nil, to: nil)
      from_date = from ? Date.parse(from) : nil
      to_date = to ? Date.parse(to) : nil

      backups = recovery_manager.list_available_backups(from: from_date, to: to_date)

      if backups.empty?
        puts 'No backups found'
        return
      end

      display_backups_table(backups)
    end

    def backup_restore(backup_id, components: nil, force: false)
      parsed_components = parse_components(components)

      unless force
        component_text = parsed_components ? "components: #{parsed_components.join(', ')}" : 'all components'
        unless yes?("Are you sure you want to restore #{backup_id} (#{component_text})? This will overwrite current data.")
          return puts 'Restoration cancelled'
        end
      end

      puts "Restoring backup: #{backup_id}"
      puts "Restoring components: #{parsed_components.join(', ')}" if parsed_components

      result = recovery_manager.restore_backup(backup_id, components: parsed_components)

      display_restoration_progress(result)
      display_restoration_summary(result)
    end

    def backup_validate(backup_id)
      puts "Validating backup: #{backup_id}"

      result = recovery_manager.validate_backup(backup_id)

      display_validation_results(result)
    end

    def backup_status
      puts 'Backup System Status'
      puts '===================='
      puts

      # Show data sources
      sources = backup_manager.discover_backup_sources
      puts 'Data Sources:'
      display_data_sources(sources)
      puts

      # Show backup statistics
      estimated_size = backup_manager.estimated_backup_size
      puts "Estimated backup size: #{human_size(estimated_size)}"
      puts

      # Show available backups
      backups = recovery_manager.list_available_backups
      completed_backups = backups.select { |b| b[:status] == 'completed' }
      total_storage = completed_backups.sum { |b| b[:size] || 0 }

      puts "Available backups: #{backups.size}"
      puts "Total backup storage: #{human_size(total_storage)}"
    end

    private

    def backup_manager
      @backup_manager ||= BackupManager.new(platform_config, docker_manager)
    end

    def recovery_manager
      @recovery_manager ||= RecoveryManager.new(backup_manager, platform_config, docker_manager)
    end

    def display_backup_progress(result)
      result[:components].each do |component, data|
        if data[:status] == 'completed'
          case component
          when 'databases'
            puts "✅ Databases: #{data[:count]} databases backed up"
          when 'redis'
            puts '✅ Redis: Data exported'
          when 'repositories'
            puts "✅ Repositories: #{data[:count]} repositories archived"
          else
            puts "✅ #{component.capitalize}: Completed"
          end
        else
          puts "❌ #{component.capitalize}: #{data[:error]}"
        end
      end
    end

    def display_backup_summary(result)
      case result[:status]
      when 'completed'
        puts 'Backup completed successfully'
      when 'partial'
        puts 'Backup completed with errors'
      else
        puts 'Backup failed'
      end

      puts "Total size: #{human_size(result[:size])}"
      puts "Duration: #{result[:duration]} seconds"
    end

    def display_backups_table(backups)
      puts 'Available Backups'
      puts '=================='
      puts

      # Table header
      printf "%-25s %-12s %-10s %-12s %s\n", 'Backup ID', 'Type', 'Status', 'Size', 'Created'
      puts '-' * 80

      backups.each do |backup|
        printf "%-25s %-12s %-10s %-12s %s\n",
               backup[:backup_id],
               backup[:type] || 'unknown',
               backup[:status],
               human_size(backup[:size] || 0),
               backup[:created_at].strftime('%Y-%m-%d %H:%M')
      end
    end

    def display_restoration_progress(result)
      puts "✅ Recovery point created: #{result[:recovery_point]}" if result[:recovery_point]

      result[:components_restored].each do |component, data|
        if data[:status] == 'restored'
          case component
          when 'databases'
            puts "✅ Databases: #{data[:count]} databases restored"
          when 'redis'
            puts '✅ Redis: Data restored'
          when 'repositories'
            puts "✅ Repositories: #{data[:count]} repositories restored"
          else
            puts "✅ #{component.capitalize}: Restored"
          end
        else
          puts "❌ #{component.capitalize}: #{data[:error]}"
        end
      end
    end

    def display_restoration_summary(result)
      case result[:status]
      when 'completed'
        puts 'Restoration completed successfully'
      when 'partial'
        puts 'Restoration completed with errors'
      else
        puts 'Restoration failed'
      end

      puts "Duration: #{result[:duration]} seconds"
    end

    def display_validation_results(result)
      result[:checks].each do |check, status|
        icon = status ? '✅' : '❌'
        case check
        when :files_exist
          message = status ? 'All backup files present' : 'Missing backup files'
          puts "#{icon} Files exist: #{message}"
        when :checksums_valid
          message = status ? 'All files verified' : 'Verification failed'
          puts "#{icon} Checksums: #{message}"
        when :metadata_valid
          message = status ? 'Backup metadata valid' : 'Invalid metadata'
          puts "#{icon} Metadata: #{message}"
        end
      end

      puts
      if result[:valid]
        puts 'Backup validation passed'
      else
        puts 'Backup validation failed'
        puts
        puts 'Issues found:'
        result[:errors].each { |error| puts "  • #{error}" }
      end
    end

    def display_data_sources(sources)
      sources.each do |category, data|
        case category
        when :databases
          count = data.is_a?(Hash) ? data.size : 0
          total_size = data.is_a?(Hash) ? data.values.sum { |db| db[:size] || 0 } : 0
          puts "  Databases: #{count} database#{'s' if count != 1} (#{human_size(total_size)})"
        when :redis
          size = data.is_a?(Hash) ? data[:size] || 0 : 0
          puts "  Redis: #{human_size(size)}"
        when :repositories
          count = data.is_a?(Hash) ? data.size : 0
          total_size = data.is_a?(Hash) ? data.values.sum { |repo| repo[:size] || 0 } : 0
          puts "  Repositories: #{count} repositor#{if count != 1
                                                      'ies'
                                                    end}#{'y' if count == 1} (#{human_size(total_size)})"
        else
          size = data.is_a?(Hash) && data[:size] ? data[:size] : 0
          puts "  #{category.capitalize}: #{human_size(size)}"
        end
      end
    end

    def parse_components(components_string)
      return nil unless components_string

      components_string.split(',').map(&:strip)
    end

    def human_size(bytes)
      return '0 B' if bytes.zero?

      units = %w[B KB MB GB TB]
      index = 0
      size = bytes.to_f

      while size >= 1024 && index < units.size - 1
        size /= 1024.0
        index += 1
      end

      "#{size.round(1)} #{units[index]}"
    end

    # Abstract methods that should be implemented by the including class
    def platform_config
      raise NotImplementedError, 'platform_config method must be implemented by including class'
    end

    def docker_manager
      raise NotImplementedError, 'docker_manager method must be implemented by including class'
    end

    def yes?(question)
      # Default implementation - should be overridden by Thor CLI
      puts question
      true
    end
  end
end
