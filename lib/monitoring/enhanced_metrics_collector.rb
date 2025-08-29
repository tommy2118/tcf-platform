# frozen_string_literal: true

require 'net/http'
require 'json'
require 'open3'
require_relative '../docker_manager'
require_relative '../service_registry'

module TcfPlatform
  module Monitoring
    # Enhanced metrics collector with advanced features
    class EnhancedMetricsCollector
      DEFAULT_CONFIG = {
        collection_timeout: 10,
        retry_attempts: 2,
        metrics_cache_ttl: 30
      }.freeze

      attr_reader :collection_timeout, :retry_attempts, :metrics_cache_ttl

      def initialize(config = {})
        @config = DEFAULT_CONFIG.merge(config)
        @collection_timeout = @config[:collection_timeout]
        @retry_attempts = @config[:retry_attempts]
        @metrics_cache_ttl = @config[:metrics_cache_ttl]
        
        @docker_manager = DockerManager.new
        @service_registry = ServiceRegistry.new
        @metrics_cache = {}
        @cache_timestamps = {}
      end

      def collect_comprehensive_metrics(bypass_cache: false)
        return cached_metrics if !bypass_cache && cache_valid?

        collection_start = Time.now
        
        begin
          # Get service status and Docker stats
          service_status = @service_registry.all_services
          docker_stats = @docker_manager.service_stats

          # Build comprehensive metrics
          metrics = {
            services: build_service_metrics(service_status, docker_stats),
            system: collect_system_metrics,
            metadata: build_collection_metadata(collection_start, service_status)
          }

          # Cache the results
          cache_metrics(metrics)
          metrics

        rescue StandardError => e
          raise CollectionError.new("Failed to collect comprehensive metrics: #{e.message}")
        end
      end

      def collect_application_metrics(service_name)
        begin
          service_metrics = fetch_service_metrics(service_name, '/metrics')
          
          # Transform service-specific metrics
          {
            http_requests_total: service_metrics['http_requests_total'],
            avg_response_time_seconds: service_metrics['http_request_duration_seconds_avg'],
            active_connections: service_metrics['active_connections']
          }
        rescue Net::HTTPError, StandardError
          { custom_metrics_available: false }
        end
      end

      def collect_with_retries(&block)
        attempts = 0
        last_error = nil

        begin
          attempts += 1
          return block.call
        rescue StandardError => e
          last_error = e
          retry if attempts <= @retry_attempts
        end

        # All retries exhausted
        error = CollectionError.new(
          "Collection failed after #{@retry_attempts} attempts: #{last_error.message}",
          retry_count: @retry_attempts,
          original_error: last_error
        )
        raise error
      end

      def collect_historical_trends(service, metric, time_window_seconds)
        history_data = metrics_history
        service_data = history_data.select { |h| h[:services]&.dig(service.to_sym, metric.to_sym) }
        
        return {} if service_data.empty?

        values = service_data.map { |h| h[:services][service.to_sym][metric.to_sym] }
        timestamps = service_data.map { |h| h[:timestamp] }

        {
          trend_direction: calculate_trend_direction(values),
          average_change_per_minute: calculate_average_change(values, timestamps),
          volatility_score: calculate_volatility(values),
          prediction_next_5min: predict_next_value(values, 5)
        }
      end

      def detect_metric_anomalies(service, metric, time_window_seconds)
        history_data = metrics_history
        service_data = history_data.select { |h| h[:services]&.dig(service.to_sym, metric.to_sym) }
        
        return [] if service_data.size < 3

        values = service_data.map { |h| h[:services][service.to_sym][metric.to_sym] }
        mean = values.sum / values.size.to_f
        std_dev = Math.sqrt(values.map { |v| (v - mean) ** 2 }.sum / values.size)
        
        anomalies = []
        service_data.each_with_index do |data, index|
          value = values[index]
          z_score = std_dev > 0 ? (value - mean) / std_dev : 0
          
          if z_score.abs > 2.0 # Anomaly threshold
            anomalies << {
              timestamp: data[:timestamp],
              value: value,
              anomaly_score: z_score.abs / 2.0
            }
          end
        end

        anomalies
      end

      def calculate_service_health_score(service_name, metrics)
        component_scores = {}
        
        # CPU score (0-100, lower is better)
        cpu_score = [100 - metrics[:cpu_percent], 0].max
        component_scores[:cpu] = cpu_score

        # Memory score  
        memory_score = [100 - metrics[:memory_percent], 0].max
        component_scores[:memory] = memory_score

        # Response time score (anything under 500ms is good)
        response_score = metrics[:response_time_ms] ? [100 - (metrics[:response_time_ms] / 10), 0].max : 100
        component_scores[:response_time] = response_score

        # Error rate score
        error_score = metrics[:error_rate_percent] ? [100 - (metrics[:error_rate_percent] * 5), 0].max : 100
        component_scores[:error_rate] = error_score

        # Calculate overall weighted score
        overall_score = (
          component_scores[:cpu] * 0.3 +
          component_scores[:memory] * 0.3 +
          component_scores[:response_time] * 0.2 +
          component_scores[:error_rate] * 0.2
        ).round(1)

        {
          overall_score: overall_score,
          component_scores: component_scores
        }
      end

      def analyze_service_health(service_name, metrics)
        health_score_data = calculate_service_health_score(service_name, metrics)
        overall_score = health_score_data[:overall_score]

        health_status = case overall_score
                       when 80..100
                         'excellent'
                       when 60..79
                         'good'
                       when 40..59
                         'warning'
                       else
                         'critical'
                       end

        at_risk_factors = []
        recommendations = []

        # Analyze individual components
        if metrics[:cpu_percent] && metrics[:cpu_percent] > 80
          at_risk_factors << 'cpu'
          recommendations << 'Consider scaling CPU resources or optimizing CPU-intensive operations'
        end

        if metrics[:memory_percent] && metrics[:memory_percent] > 85
          at_risk_factors << 'memory'
          recommendations << 'Monitor memory usage and consider increasing memory allocation'
        end

        if metrics[:response_time_ms] && metrics[:response_time_ms] > 1000
          at_risk_factors << 'response_time'
          recommendations << 'Investigate slow response times and optimize performance'
        end

        if metrics[:error_rate_percent] && metrics[:error_rate_percent] > 5
          at_risk_factors << 'error_rate'
          recommendations << 'High error rate detected - investigate application logs'
        end

        if health_status == 'critical'
          recommendations.unshift('Service requires immediate attention - multiple components at risk')
        end

        {
          health_status: health_status,
          at_risk_factors: at_risk_factors,
          recommendations: recommendations,
          overall_score: overall_score
        }
      end

      def export_metrics_batch(metrics_data)
        batch = []

        # Validate structure
        unless metrics_data.is_a?(Hash) && metrics_data[:services]
          raise ExportError, "Invalid metrics data structure"
        end

        # Process services metrics
        metrics_data[:services].each do |service, service_metrics|
          service_metrics.each do |metric_name, value|
            next if metric_name == :timestamp

            batch << {
              service: service.to_s,
              metric: metric_name.to_s,
              value: value,
              timestamp: Time.now.to_i
            }
          end
        end

        # Process system metrics
        if metrics_data[:system]
          metrics_data[:system].each do |metric_name, value|
            next if metric_name == :timestamp

            batch << {
              service: 'system',
              metric: metric_name.to_s,
              value: value,
              timestamp: Time.now.to_i
            }
          end
        end

        batch
      end

      private

      def build_service_metrics(service_status, docker_stats)
        services = {}

        service_status.each do |service_name, status|
          service_key = normalize_service_name(service_name)
          container_key = find_container_for_service(service_name, docker_stats.keys)
          
          services[service_key] = {
            health_status: status[:health] || 'unknown'
          }

          # Add Docker stats if available
          if container_key && docker_stats[container_key]
            stats = docker_stats[container_key]
            services[service_key].merge!(parse_docker_stats(stats))
          end
        end

        services
      end

      def collect_system_metrics
        {
          load_average: collect_system_load,
          disk_usage_percent: collect_disk_metrics[:usage_percent],
          disk_available_bytes: collect_disk_metrics[:available_bytes],
          network_interfaces: collect_network_metrics[:interfaces]
        }
      end

      def build_collection_metadata(start_time, service_status)
        duration_ms = ((Time.now - start_time) * 1000).round(2)
        healthy_count = service_status.count { |_, status| status[:health] == 'healthy' }
        
        {
          collection_timestamp: start_time,
          collection_duration_ms: duration_ms,
          total_services_discovered: service_status.size,
          healthy_services_count: healthy_count,
          unhealthy_services_count: service_status.size - healthy_count,
          from_cache: false
        }
      end

      def cache_valid?
        return false if @metrics_cache.empty?
        
        cache_age = Time.now - (@cache_timestamps[:last_update] || Time.at(0))
        cache_age < @metrics_cache_ttl
      end

      def cached_metrics
        @metrics_cache.dup.tap do |cached|
          cached[:metadata][:from_cache] = true if cached[:metadata]
        end
      end

      def cache_metrics(metrics)
        @metrics_cache = metrics.dup
        @cache_timestamps[:last_update] = Time.now
      end

      def normalize_service_name(service_name)
        # Convert 'tcf-gateway' to :gateway
        service_name.to_s.gsub(/^tcf-/, '').to_sym
      end

      def find_container_for_service(service_name, container_names)
        pattern = service_name.to_s.gsub('tcf-', '')
        container_names.find { |name| name.include?(pattern) }
      end

      def parse_docker_stats(stats)
        {
          cpu_percent: parse_percentage(stats['CPUPerc']),
          memory_percent: parse_percentage(stats['MemPerc']),
          memory_usage_mb: parse_memory_usage(stats['MemUsage']),
          network_rx_bytes: parse_network_io(stats['NetIO'])[:rx],
          network_tx_bytes: parse_network_io(stats['NetIO'])[:tx],
          disk_read_bytes: parse_disk_io(stats['BlockIO'])[:read],
          disk_write_bytes: parse_disk_io(stats['BlockIO'])[:write],
          process_count: stats['PIDs'].to_i
        }
      end

      def parse_percentage(percent_str)
        percent_str.to_s.gsub('%', '').to_f
      end

      def parse_memory_usage(mem_str)
        # Parse "128.5MiB / 1.952GiB" format
        parts = mem_str.split(' / ')
        used_part = parts.first
        
        if used_part.include?('MiB')
          used_part.gsub('MiB', '').to_f
        elsif used_part.include?('GiB')
          used_part.gsub('GiB', '').to_f * 1024
        else
          0.0
        end
      end

      def parse_network_io(netio_str)
        # Parse "1.23kB / 2.34kB" format
        parts = netio_str.split(' / ')
        rx = parse_bytes(parts[0])
        tx = parse_bytes(parts[1])
        { rx: rx, tx: tx }
      end

      def parse_disk_io(blockio_str)
        # Parse "4.56MB / 1.23MB" format  
        parts = blockio_str.split(' / ')
        read = parse_bytes(parts[0])
        write = parse_bytes(parts[1])
        { read: read, write: write }
      end

      def parse_bytes(byte_str)
        return 0 if byte_str.nil?

        case byte_str
        when /(\d+\.?\d*)\s*GB/
          ($1.to_f * 1_000_000_000).to_i
        when /(\d+\.?\d*)\s*MB/
          ($1.to_f * 1_000_000).to_i
        when /(\d+\.?\d*)\s*kB/
          ($1.to_f * 1000).to_i
        when /(\d+\.?\d*)\s*B/
          $1.to_i
        else
          0
        end
      end

      def collect_system_load
        # Mock system load - in real implementation would use system calls
        2.45
      end

      def collect_disk_metrics
        # Mock disk metrics
        {
          usage_percent: 78.3,
          available_bytes: 50_000_000_000,
          total_bytes: 200_000_000_000
        }
      end

      def collect_network_metrics
        # Mock network metrics
        {
          interfaces: {
            'eth0' => { rx_bytes: 1_000_000, tx_bytes: 2_000_000 }
          }
        }
      end

      def fetch_service_metrics(service_name, endpoint)
        # Mock implementation for testing
        {
          'http_requests_total' => 15432,
          'http_request_duration_seconds_avg' => 0.145,
          'active_connections' => 25
        }
      end

      def metrics_history
        # Mock implementation - would normally fetch from storage
        []
      end

      def calculate_trend_direction(values)
        return 'stable' if values.size < 2

        increases = 0
        decreases = 0
        
        (1...values.size).each do |i|
          if values[i] > values[i-1]
            increases += 1
          elsif values[i] < values[i-1]
            decreases += 1
          end
        end

        if increases > decreases
          'increasing'
        elsif decreases > increases
          'decreasing'
        else
          'stable'
        end
      end

      def calculate_average_change(values, timestamps)
        return 0.0 if values.size < 2

        total_change = values.last - values.first
        time_span_minutes = (timestamps.last - timestamps.first) / 60.0
        
        time_span_minutes > 0 ? total_change / time_span_minutes : 0.0
      end

      def calculate_volatility(values)
        return 0.0 if values.size < 2

        mean = values.sum / values.size.to_f
        variance = values.sum { |v| (v - mean) ** 2 } / values.size.to_f
        Math.sqrt(variance) / mean
      end

      def predict_next_value(values, minutes_ahead)
        return values.last if values.size < 2

        # Simple linear extrapolation
        recent_values = values.last(5) # Use last 5 points
        trend = calculate_simple_trend(recent_values)
        
        values.last + (trend * minutes_ahead)
      end

      def calculate_simple_trend(values)
        return 0.0 if values.size < 2

        changes = []
        (1...values.size).each do |i|
          changes << values[i] - values[i-1]
        end

        changes.sum / changes.size.to_f
      end
    end
  end
end