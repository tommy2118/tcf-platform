# frozen_string_literal: true

require 'thor'
require_relative '../repository_manager'
require_relative '../build_coordinator'
require_relative '../config_manager'

module TcfPlatform
  module RepositoryCommands
    def self.included(base)
      base.class_eval do
        desc 'repos SUBCOMMAND [ARGS]', 'Repository management commands'
        long_desc <<-LONGDESC
          Repository management commands for TCF Platform services.

          Available subcommands:
            status                    Show status of all repositories
            clone [SERVICE...]        Clone missing repositories (all or specific)
            update [SERVICE...]       Update existing repositories (all or specific)

          Examples:
            tcf-platform repos status
            tcf-platform repos clone
            tcf-platform repos clone tcf-personas tcf-workflows
            tcf-platform repos update
            tcf-platform repos update tcf-gateway
        LONGDESC
        def repos(subcommand, *services)
          case subcommand
          when 'status'
            repos_status
          when 'clone'
            repos_clone(services.empty? ? nil : services)
          when 'update'
            repos_update(services.empty? ? nil : services)
          else
            puts "❌ Unknown subcommand: #{subcommand}"
            puts "Available subcommands: status, clone, update"
            exit 1
          end
        end

        desc 'build [SERVICE...] [OPTIONS]', 'Build TCF Platform services'
        option :parallel, type: :boolean, default: false, desc: 'Build independent services in parallel'
        long_desc <<-LONGDESC
          Build TCF Platform services in dependency order.

          Examples:
            tcf-platform build                    # Build all services
            tcf-platform build tcf-personas       # Build specific service
            tcf-platform build --parallel         # Build independent services in parallel
        LONGDESC
        def build(*services)
          services_to_build = services.empty? ? nil : services

          if options[:parallel] && services_to_build.nil?
            build_parallel
          else
            build_sequential(services_to_build)
          end
        end

        desc 'build-status', 'Show build status of all TCF Platform services'
        def build_status
          puts '📊 TCF Platform Build Status'
          puts '=' * 50

          status_data = build_coordinator.build_status
          built_count = 0
          total_size = 0.0

          status_data.each do |service_name, info|
            case info[:status]
            when 'built'
              built_count += 1
              total_size += info[:size_mb] || 0.0
              age_display = info[:age_hours] ? "#{info[:age_hours].round(1)}h ago" : 'unknown'
              size_display = info[:size_mb] ? "#{info[:size_mb]} MB" : 'unknown'
              created_display = info[:created] ? info[:created].strftime('%b %d, %Y %H:%M') : 'unknown'

              puts "✅ #{service_name.ljust(15)} Built    #{age_display.ljust(10)} #{size_display.ljust(10)} #{info[:image_id]&.slice(7, 12) || 'unknown'}"
              puts "   📅 Created: #{created_display}"
            when 'not_built'
              puts "❌ #{service_name.ljust(15)} Not built"
            end
          end

          puts
          puts '📋 Build status summary:'
          puts "   Built: #{built_count}/#{status_data.size} services"
          puts "   Total size: #{total_size.round(1)} MB" if total_size > 0
        end
      end
    end

    private

    def repos_status
      puts '📋 TCF Platform Repository Status'
      puts '=' * 50

      status_data = repository_manager.repository_status
      missing_repos = []

      status_data.each do |repo_name, info|
        if info[:exists]
          if info[:git_repository]
            branch_info = info[:current_branch] || 'unknown'
            clean_status = info[:clean] ? 'Clean working directory' : 'Uncommitted changes'
            commit_info = info[:latest_commit]

            puts "✅ #{repo_name.ljust(15)} #{branch_info.ljust(20)} #{commit_info[:hash]&.slice(0, 7) || 'unknown'}"
            puts "   📂 Path: #{info[:path]}"
            puts "   🔧 #{clean_status}"

            if commit_info
              puts "   📝 Latest commit: #{commit_info[:message]}"
              puts "   👤 Author: #{commit_info[:author]} (#{commit_info[:date]&.strftime('%b %d, %Y') || 'unknown'})"
            end
          else
            puts "⚠️  #{repo_name.ljust(15)} Directory exists but not a git repository"
            puts "   📂 Path: #{info[:path]}"
          end
        else
          missing_repos << repo_name
          puts "❌ #{repo_name.ljust(15)} Missing"
          puts "   📂 Expected path: #{info[:path]}"
        end
        puts
      end

      return unless missing_repos.any?

      puts '⚠️  Missing repositories found:'
      puts "   #{missing_repos.join(', ')}"
      puts "   Run 'tcf-platform repos clone' to clone missing repositories"
    end

    def repos_clone(services)
      if services
        puts "🔄 Cloning specified repositories: #{services.join(', ')}"
      else
        puts '🔄 Cloning missing repositories...'
      end

      results = repository_manager.clone_missing_repositories(services)
      successful = 0
      failed = 0

      results.each do |repo_name, result|
        case result[:status]
        when 'cloned'
          successful += 1
          puts "✅ #{repo_name.ljust(15)} cloned successfully"
          puts "   📂 Path: #{result[:path]}"
          puts "   🔗 URL: #{result[:url]}"
        when 'failed'
          failed += 1
          puts "❌ #{repo_name.ljust(15)} failed to clone"
          puts "   💥 Error: #{result[:error]}"
        end
      end

      puts
      puts 'Repository cloning completed:'
      puts "   #{successful} successful, #{failed} failed"
    end

    def repos_update(services)
      if services
        puts "🔄 Updating specified repositories: #{services.join(', ')}"
      else
        puts '🔄 Updating repositories...'
      end

      results = repository_manager.update_repositories(services)
      successful = 0
      failed = 0

      results.each do |repo_name, result|
        case result[:status]
        when 'updated'
          successful += 1
          commit_info = result[:latest_commit]

          puts "✅ #{repo_name.ljust(15)} updated successfully"
          puts "   📂 Path: #{result[:path]}"

          if commit_info
            puts "   📝 Latest: #{commit_info[:hash]&.slice(0, 7) || 'unknown'} - #{commit_info[:message]}"
            puts "   👤 Author: #{commit_info[:author]} (#{commit_info[:date]&.strftime('%b %d, %Y') || 'unknown'})"
          end
        when 'failed'
          failed += 1
          puts "❌ #{repo_name.ljust(15)} failed to update"
          puts "   💥 Error: #{result[:error]}"
        end
      end

      puts
      puts 'Repository updates completed:'
      puts "   #{successful} successful, #{failed} failed"
    end

    def build_sequential(services_to_build)
      if services_to_build
        puts "🔨 Building services: #{services_to_build.join(', ')}"
      else
        puts '🔨 Building TCF Platform services...'
        build_order = build_coordinator.calculate_build_order
        puts "Building in dependency order: #{build_order.join(' → ')}"
      end

      results = build_coordinator.build_services(services_to_build)
      successful = 0
      failed = 0
      total_time = 0.0
      total_size = 0.0

      results.each do |service_name, result|
        case result[:status]
        when 'success'
          successful += 1
          time_display = result[:build_time] ? "#{result[:build_time]}s" : 'unknown'
          size_display = result[:size_mb] ? "#{result[:size_mb]} MB" : 'unknown'
          total_time += result[:build_time] || 0.0
          total_size += result[:size_mb] || 0.0

          puts "✅ #{service_name.ljust(15)} success   #{time_display.ljust(8)} #{size_display.ljust(8)} #{result[:image_id]&.slice(7, 12) || 'unknown'}"
        when 'failed'
          failed += 1
          puts "❌ #{service_name.ljust(15)} failed"
          puts "   💥 Error: #{result[:error]}"
        when 'skipped'
          puts "⏭️  #{service_name.ljust(15)} skipped   (#{result[:reason]})"
        end
      end

      puts
      puts 'Build completed:'
      puts "   #{successful} successful, #{failed} failed"
      puts "   Total time: #{total_time.round(1)}s, Total size: #{total_size.round(1)} MB" if total_time > 0
    end

    def build_parallel
      puts '⚡ Building services in parallel...'

      # Get independent services (no dependencies)
      dependencies = build_coordinator.analyze_dependencies
      independent_services = dependencies.select { |_, deps| deps.empty? }.keys

      if independent_services.empty?
        puts 'No independent services found for parallel building'
        return
      end

      puts "Building independent services: #{independent_services.join(', ')}"

      results = build_coordinator.parallel_build(independent_services)
      successful = 0
      failed = 0

      results.each do |service_name, result|
        case result[:status]
        when 'success'
          successful += 1
          time_display = result[:build_time] ? "#{result[:build_time]}s" : 'unknown'
          size_display = result[:size_mb] ? "#{result[:size_mb]} MB" : 'unknown'

          puts "✅ #{service_name.ljust(15)} success   #{time_display.ljust(8)} #{size_display}"
        when 'failed'
          failed += 1
          puts "❌ #{service_name.ljust(15)} failed"
          puts "   💥 Error: #{result[:error]}"
        end
      end

      puts
      puts "#{successful} services built successfully in parallel"
    end

    def repository_manager
      @repository_manager ||= begin
        config = TcfPlatform::ConfigManager.load_environment
        TcfPlatform::RepositoryManager.new(config)
      end
    end

    def build_coordinator
      @build_coordinator ||= begin
        config = TcfPlatform::ConfigManager.load_environment
        repo_manager = repository_manager
        TcfPlatform::BuildCoordinator.new(repo_manager, config)
      end
    end
  end
end