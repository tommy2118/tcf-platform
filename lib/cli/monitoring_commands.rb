# frozen_string_literal: true

require_relative '../monitoring/monitoring_service'
require_relative '../monitoring/prometheus_exporter'
require_relative '../monitoring/time_series_storage'

module TcfPlatform
  class CLI < Thor
    # Monitoring and metrics commands for TCF Platform
    module MonitoringCommands
      def self.included(base)
        base.class_eval do
          # Metrics display commands
          desc 'metrics-show [SERVICE]', 'Display current metrics for services'
          option :format, type: :string, default: 'table', desc: 'Output format: table, json, csv'
          option :refresh, type: :boolean, default: false, desc: 'Auto-refresh display'
          def metrics_show(service = nil)
            metrics_collector = TcfPlatform::MetricsCollector.new
            
            begin
              current_metrics = metrics_collector.collect_service_metrics
              
              if service
                display_service_metrics(service, current_metrics)
              else
                display_all_metrics(current_metrics)
              end
            rescue StandardError => e
              puts "Error collecting metrics: #{e.message}"
            end
          end

          # Prometheus export command
          desc 'metrics-export', 'Export metrics in Prometheus format'
          option :output, type: :string, desc: 'Output file path'
          def metrics_export
            prometheus_exporter = TcfPlatform::Monitoring::PrometheusExporter.new
            
            begin
              prometheus_output = prometheus_exporter.generate_complete_export
              
              if options[:output]
                File.write(options[:output], prometheus_output)
                puts "Metrics exported to #{options[:output]}"
              else
                puts prometheus_output
              end
            rescue StandardError => e
              puts "Error writing to file: #{e.message}"
            end
          end

          # Historical metrics query
          desc 'metrics-query SERVICE METRIC', 'Query historical metrics data'
          option :start_time, type: :string, desc: 'Start time (ISO 8601 format)'
          option :end_time, type: :string, desc: 'End time (ISO 8601 format)'
          option :aggregation, type: :string, desc: 'Aggregation function: avg, min, max, sum'
          option :resolution, type: :numeric, default: 300, desc: 'Time resolution in seconds'
          def metrics_query(service, metric)
            time_series_storage = TcfPlatform::Monitoring::TimeSeriesStorage.new
            
            query_params = build_query_params(service, metric)
            result = time_series_storage.query_metrics(query_params)
            
            if result.empty?
              puts 'No data found for the specified query'
            else
              display_historical_metrics(service, metric, result)
            end
          end

          # Monitoring service control
          desc 'monitor-start', 'Start monitoring system'
          option :background, type: :boolean, default: true, desc: 'Run in background'
          def monitor_start
            monitoring_service = TcfPlatform::Monitoring::MonitoringService.new
            
            if monitoring_service.running?
              puts 'Monitoring system is already running'
              return
            end

            puts '📊 Starting monitoring system...'
            
            begin
              monitoring_service.start
              
              if monitoring_service.running?
                if options[:background]
                  puts '✅ Monitoring system started successfully in background mode'
                else
                  puts '✅ Monitoring system started successfully'
                end
              else
                puts '❌ Failed to start monitoring system'
              end
            rescue StandardError => e
              puts "❌ Failed to start monitoring: #{e.message}"
            end
          end

          desc 'monitor-stop', 'Stop monitoring system'
          def monitor_stop
            monitoring_service = TcfPlatform::Monitoring::MonitoringService.new
            
            if !monitoring_service.running?
              puts 'Monitoring system is not running'
              return
            end

            puts '🛑 Stopping monitoring system...'
            
            monitoring_service.stop
            
            if !monitoring_service.running?
              puts '✅ Monitoring system stopped successfully'
            else
              puts '❌ Failed to stop monitoring system'
            end
          end

          desc 'monitor-status', 'Show monitoring system status'
          option :verbose, type: :boolean, default: false, desc: 'Show detailed information'
          def monitor_status
            monitoring_service = TcfPlatform::Monitoring::MonitoringService.new
            monitoring_stats = monitoring_service.status
            
            puts 'Monitoring System Status'
            puts '=' * 40
            puts "Status: #{monitoring_stats[:running] ? '✅ Running' : '❌ Stopped'}"
            
            if monitoring_stats[:running]
              puts "Uptime: #{format_duration(monitoring_stats[:uptime])}"
              puts "Metrics Collected: #{number_with_commas(monitoring_stats[:metrics_collected])}"
              puts "Last Collection: #{time_ago(monitoring_stats[:last_collection])}"
              puts "Storage Size: #{monitoring_stats[:storage_size_mb]} MB"
              puts "Errors: #{monitoring_stats[:errors_count]}"
            end
            
            if options[:verbose]
              display_verbose_monitoring_status
            end
          end

          desc 'monitor-dashboard', 'Start monitoring dashboard'
          option :port, type: :numeric, default: 3001, desc: 'Dashboard port'
          option :host, type: :string, default: 'localhost', desc: 'Dashboard host'
          def monitor_dashboard
            monitoring_service = TcfPlatform::Monitoring::MonitoringService.new
            
            puts '🖥️  Starting monitoring dashboard...'
            
            begin
              dashboard_config = { port: options[:port], host: options[:host] }
              result = monitoring_service.start_dashboard(dashboard_config)
              
              puts "Dashboard available at: #{result[:url]}"
            rescue StandardError => e
              puts "❌ Failed to start dashboard: #{e.message}"
            end
          end

          desc 'metrics-history', 'Show historical metrics collection data'
          option :limit, type: :numeric, default: 20, desc: 'Limit number of results'
          option :service, type: :string, desc: 'Filter by service name'
          def metrics_history
            metrics_collector = TcfPlatform::MetricsCollector.new
            history_data = metrics_collector.metrics_history
            
            puts 'Metrics Collection History'
            puts '=' * 50
            
            limited_history = history_data.last(options[:limit])
            
            limited_history.each do |entry|
              display_history_entry(entry)
            end
          end

          desc 'monitor-cleanup', 'Clean up expired metrics data'
          option :dry_run, type: :boolean, default: false, desc: 'Show what would be deleted'
          def monitor_cleanup
            time_series_storage = TcfPlatform::Monitoring::TimeSeriesStorage.new
            
            if options[:dry_run]
              puts '🧹 DRY RUN: Analyzing expired metrics...'
            else
              puts '🧹 Cleaning up expired metrics...'
            end
            
            cleanup_stats = time_series_storage.cleanup_expired_metrics(dry_run: options[:dry_run])
            
            puts "Scanned: #{number_with_commas(cleanup_stats[:scanned_keys])} keys"
            
            if options[:dry_run]
              puts "Would delete: #{cleanup_stats[:expired_keys]} expired keys"
              puts "Would free: #{cleanup_stats[:storage_freed_mb]} MB"
            else
              puts "Deleted: #{cleanup_stats[:deleted_keys]} expired keys"
              puts "Freed: #{cleanup_stats[:storage_freed_mb]} MB"
            end
            
            puts "Duration: #{cleanup_stats[:cleanup_duration]} seconds"
          end

          private

          def display_service_metrics(service_name, metrics)
            service_data = metrics[service_name.to_sym]
            
            if service_data.nil?
              puts "Service \"#{service_name}\" not found"
              return
            end
            
            puts "Metrics for #{service_name}"
            puts '-' * 30
            puts "CPU: #{service_data[:cpu_percent]}%"
            puts "Memory: #{service_data[:memory_percent]}%"
            puts "Response Time: #{service_data[:response_time_ms]}ms" if service_data[:response_time_ms]
            puts "Status: #{service_data[:status]}" if service_data[:status]
          end

          def display_all_metrics(metrics)
            puts 'TCF Platform Metrics'
            puts '=' * 40
            
            healthy_count = metrics.values.count { |m| m[:status] == 'healthy' }
            total_services = metrics.size
            
            puts "System Status: #{healthy_count == total_services ? '✅' : '⚠️'}"
            puts "Services Running: #{healthy_count}/#{total_services}"
            puts ''
            
            metrics.each do |service, data|
              puts "#{service.to_s.capitalize}:"
              puts "  CPU: #{data[:cpu_percent]}%"
              puts "  Memory: #{data[:memory_percent]}%"
              puts "  Response Time: #{data[:response_time_ms]}ms" if data[:response_time_ms]
              puts ''
            end
          end

          def display_historical_metrics(service, metric, data)
            puts "Historical data for #{service} #{metric}"
            puts '-' * 40
            
            data.each do |point|
              timestamp = Time.at(point[:timestamp])
              puts "#{timestamp.strftime('%Y-%m-%d %H:%M:%S')}: #{point[:value]}"
            end
          end

          def display_verbose_monitoring_status
            time_series_storage = TcfPlatform::Monitoring::TimeSeriesStorage.new
            storage_stats = time_series_storage.storage_statistics
            
            puts ''
            puts 'Storage Details'
            puts '-' * 20
            puts "Used Memory: #{(storage_stats[:used_memory_bytes] / (1024.0 * 1024)).round(1)} MB"
            puts "Total Keys: #{number_with_commas(storage_stats[:total_keys])}"
            puts "Cache Hit Rate: #{storage_stats[:cache_hit_rate]}%"
          end

          def display_history_entry(entry)
            timestamp = entry[:timestamp].strftime('%Y-%m-%d %H:%M:%S')
            service_count = entry[:services]&.size || 0
            
            puts "#{timestamp} - #{service_count} services"
            
            entry[:services]&.each do |service, metrics|
              puts "  #{service}: CPU: #{metrics[:cpu_percent]}%"
            end
            puts ''
          end

          def build_query_params(service, metric)
            params = {
              service: service,
              metric: metric,
              resolution: options[:resolution] || 300
            }
            
            if options[:start_time]
              params[:start_time] = Time.parse(options[:start_time])
            else
              params[:start_time] = Time.now - 3600 # Default: 1 hour ago
            end
            
            if options[:end_time]
              params[:end_time] = Time.parse(options[:end_time])
            else
              params[:end_time] = Time.now
            end
            
            params[:aggregation] = options[:aggregation] if options[:aggregation]
            
            params
          end

          def format_duration(seconds)
            if seconds < 60
              "#{seconds.round} seconds"
            elsif seconds < 3600
              "#{(seconds / 60).round} minutes"
            else
              hours = (seconds / 3600).round
              minutes = ((seconds % 3600) / 60).round
              "#{hours} hour#{hours != 1 ? 's' : ''} #{minutes} minute#{minutes != 1 ? 's' : ''}"
            end
          end

          def time_ago(time)
            return 'Never' if time.nil?
            
            seconds_ago = Time.now - time
            
            if seconds_ago < 60
              "#{seconds_ago.round} seconds ago"
            elsif seconds_ago < 3600
              "#{(seconds_ago / 60).round} minutes ago"
            else
              "#{(seconds_ago / 3600).round} hours ago"
            end
          end

          def number_with_commas(number)
            number.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
          end
        end
      end
    end
  end
end