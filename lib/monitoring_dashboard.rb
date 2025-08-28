# frozen_string_literal: true

require 'json'
require_relative 'service_health_monitor'
require_relative 'metrics_collector'
require_relative 'alerting_system'

module TcfPlatform
  # Comprehensive real-time monitoring dashboard integrating health, metrics, and alerting
  # rubocop:disable Metrics/ClassLength
  class MonitoringDashboard
    DEFAULT_HEALTH_ENDPOINTS = {
      gateway: 'http://localhost:3000/health',
      personas: 'http://localhost:3001/health',
      workflows: 'http://localhost:3002/health',
      projects: 'http://localhost:3003/health',
      context: 'http://localhost:3004/health',
      tokens: 'http://localhost:3005/health'
    }.freeze

    def initialize(refresh_interval: 10, max_history: 100)
      @refresh_interval = refresh_interval
      @max_history = max_history
      @health_monitor = ServiceHealthMonitor.new
      @metrics_collector = MetricsCollector.new(max_history: max_history)
      @alerting_system = AlertingSystem.new(max_history: max_history)
      @monitoring_history = []
      @monitoring_active = false
      @monitoring_thread = nil
    end

    # rubocop:disable Metrics/MethodLength
    def collect_all_data
      service_metrics = @metrics_collector.collect_service_metrics
      response_metrics = @metrics_collector.collect_response_time_metrics(health_endpoints)
      aggregated_metrics = @metrics_collector.aggregate_metrics(service_metrics, response_metrics)

      @alerting_system.check_thresholds(aggregated_metrics)
      active_alerts = @alerting_system.active_alerts

      {
        health: @health_monitor.aggregate_health_status,
        metrics: aggregated_metrics,
        alerts: active_alerts,
        collected_at: Time.now
      }
    end
    # rubocop:enable Metrics/MethodLength

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def dashboard_summary
      data = collect_all_data

      {
        system_status: data[:health][:overall_status],
        services_healthy: data[:health][:healthy_count],
        services_unhealthy: data[:health][:unhealthy_count],
        total_services: data[:health][:total_services],
        avg_cpu_usage: data.dig(:metrics, :system_averages, :avg_cpu_percent) || 0.0,
        avg_memory_usage: data.dig(:metrics, :system_averages, :avg_memory_percent) || 0.0,
        avg_response_time: data.dig(:metrics, :system_averages, :avg_response_time_ms) || 0.0,
        total_alerts: data[:alerts].size,
        warning_alerts: data[:alerts].count { |alert| alert[:level] == 'warning' },
        critical_alerts: data[:alerts].count { |alert| alert[:level] == 'critical' },
        timestamp: data[:collected_at]
      }
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def service_details(service_name)
      data = collect_all_data

      # Normalize service name to match various formats
      normalized_name = normalize_service_name(service_name)
      service_key = find_service_key(data, normalized_name)

      return nil unless service_key

      health_info = data[:health][:services][service_key] || {}
      metrics_info = data[:metrics][normalized_name.to_sym] || {}
      service_alerts = data[:alerts].select { |alert| alert[:service] == service_name }

      {
        service_name: service_name,
        health_status: health_info[:health] || 'unknown',
        container_status: health_info[:status] || 'unknown',
        port: health_info[:port],
        uptime: @health_monitor.service_uptime(service_name),
        cpu_percent: metrics_info[:cpu_percent],
        memory_percent: metrics_info[:memory_percent],
        response_time_ms: metrics_info[:response_time_ms],
        network_rx_bytes: metrics_info[:network_rx_bytes],
        network_tx_bytes: metrics_info[:network_tx_bytes],
        alerts: service_alerts
      }
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    def configure_alerting(threshold_config)
      @alerting_system.configure_thresholds(threshold_config)
      @alerting_system.thresholds
    end

    def start_monitoring
      return if @monitoring_active

      @monitoring_active = true
      @monitoring_thread = Thread.new { monitoring_loop }
    end

    def stop_monitoring
      @monitoring_active = false
      @monitoring_thread&.join
      @monitoring_thread = nil
    end

    def monitoring_active?
      @monitoring_active
    end

    attr_reader :refresh_interval, :max_history, :monitoring_history

    def export_data(format = 'json')
      data = collect_all_data

      case format.downcase
      when 'json'
        export_as_json(data)
      when 'csv'
        export_as_csv(data)
      else
        raise ArgumentError, "Unsupported export format: #{format}. Supported formats: json, csv"
      end
    end

    def health_endpoints
      DEFAULT_HEALTH_ENDPOINTS
    end

    private

    def normalize_service_name(service_name)
      service_name.to_s.gsub(/^tcf-/, '').to_sym
    end

    def find_service_key(data, normalized_name)
      # Try to find the service key in health data
      service_keys = data[:health][:services].keys

      # Look for exact match first
      exact_match = service_keys.find { |key| key.include?(normalized_name.to_s) }
      return exact_match if exact_match

      # Look for partial match
      service_keys.find do |key|
        key.include?(normalized_name.to_s) || normalized_name.to_s.include?(key.gsub('tcf-', ''))
      end
    end

    def monitoring_loop
      while @monitoring_active
        begin
          data = collect_all_data
          record_monitoring_data(data)
          sleep(@refresh_interval)
        rescue StandardError => e
          # Log error but continue monitoring
          puts "Monitoring error: #{e.message}"
          sleep(@refresh_interval)
        end
      end
    end

    def record_monitoring_data(data)
      @monitoring_history << data
      @monitoring_history.shift if @monitoring_history.size > @max_history
    end

    def export_as_json(data)
      JSON.pretty_generate(data)
    end

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    def export_as_csv(data)
      csv_lines = []
      csv_lines << 'service_name,status,cpu_percent,memory_percent,response_time_ms,alerts_count'

      data[:metrics].each do |service_name, metrics|
        next if service_name == :system_averages

        health_key = find_service_key(data, service_name)
        health_status = health_key ? data[:health][:services][health_key][:status] : 'unknown'
        service_alerts = data[:alerts].select { |alert| alert[:service] == service_name.to_s }

        csv_lines << [
          service_name,
          health_status,
          metrics[:cpu_percent] || 0,
          metrics[:memory_percent] || 0,
          metrics[:response_time_ms] || 0,
          service_alerts.size
        ].join(',')
      end

      csv_lines.join("\n")
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
  end
  # rubocop:enable Metrics/ClassLength
end
