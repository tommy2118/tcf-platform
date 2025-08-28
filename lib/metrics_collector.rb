# frozen_string_literal: true

require 'json'
require 'net/http'
require 'uri'
require 'open3'

module TcfPlatform
  # Collects performance metrics from TCF Platform services
  # rubocop:disable Metrics/ClassLength
  class MetricsCollector
    SERVICE_NAME_MAP = {
      /tcf-gateway/ => :gateway,
      /tcf-personas/ => :personas,
      /tcf-workflows/ => :workflows,
      /tcf-projects/ => :projects,
      /tcf-context/ => :context,
      /tcf-tokens/ => :tokens
    }.freeze

    BYTE_MULTIPLIERS = {
      'GB' => 1_000_000_000,
      'MB' => 1_000_000,
      'kB' => 1000,
      'B' => 1
    }.freeze

    def initialize(max_history: 100)
      @max_history = max_history
      @history = []
    end

    def collect_service_metrics
      docker_stats = docker_stats_output
      return {} if docker_stats.empty?

      build_service_metrics(docker_stats)
    end

    def build_service_metrics(docker_stats)
      metrics = {}
      docker_stats.each do |container_name, stats|
        service_name = extract_service_name(container_name)
        next unless service_name

        metrics[service_name] = build_metric_hash(stats)
      end
      metrics
    end

    def build_metric_hash(stats)
      network_io = parse_network_io(stats['NetIO'])
      {
        cpu_percent: parse_cpu_percent(stats['CPUPerc']),
        memory_usage_mb: parse_memory_usage(stats['MemUsage']),
        memory_percent: parse_memory_percent(stats['MemPerc']),
        network_rx_bytes: network_io[:rx],
        network_tx_bytes: network_io[:tx],
        timestamp: Time.now
      }
    end

    def collect_response_time_metrics(health_endpoints)
      metrics = {}

      health_endpoints.each do |service_name, endpoint_url|
        response_time = measure_response_time(endpoint_url)

        metrics[service_name] = {
          response_time_ms: response_time ? (response_time * 1000).round(1) : nil,
          status: response_time ? 'responding' : 'not_responding',
          timestamp: Time.now
        }
      end

      metrics
    end

    def aggregate_metrics(service_metrics, response_metrics)
      combined = merge_service_and_response_metrics(service_metrics, response_metrics)
      combined[:system_averages] = calculate_system_averages(service_metrics, response_metrics)
      combined
    end

    def merge_service_and_response_metrics(service_metrics, response_metrics)
      all_services = (service_metrics.keys + response_metrics.keys).uniq
      combined = {}

      all_services.each do |service_name|
        combined[service_name] = {}
        combined[service_name].merge!(service_metrics[service_name]) if service_metrics[service_name]
        combined[service_name].merge!(response_metrics[service_name]) if response_metrics[service_name]
      end

      combined
    end

    def collect_and_store_metrics
      service_metrics = collect_service_metrics
      @history << service_metrics
      @history.shift if @history.size > @max_history
      service_metrics
    end

    def metrics_history
      @history
    end

    private

    def docker_stats_output
      stdout, _stderr, status = Open3.capture3('docker', 'stats', '--no-stream', '--format', 'json')
      return {} unless status.success? && !stdout.strip.empty?

      parse_docker_stats(stdout)
    rescue StandardError
      {}
    end

    def parse_docker_stats(stdout)
      stats = {}
      stdout.strip.split("\n").each do |line|
        container_stats = JSON.parse(line)
        stats[container_stats['Name']] = container_stats
      end
      stats
    end

    def extract_service_name(container_name)
      SERVICE_NAME_MAP.each { |pattern, name| return name if container_name.match?(pattern) }
      nil
    end

    def parse_cpu_percent(cpu_str)
      return 0.0 unless cpu_str

      cpu_str.gsub('%', '').to_f
    end

    def parse_memory_usage(mem_str)
      return 0.0 unless mem_str

      # Format: "128.5MiB / 1.952GiB"
      usage_part = mem_str.split(' / ').first

      if usage_part.include?('GiB')
        usage_part.gsub('GiB', '').to_f * 1024
      elsif usage_part.include?('MiB')
        usage_part.gsub('MiB', '').to_f
      else
        0.0
      end
    end

    def parse_memory_percent(mem_percent_str)
      return 0.0 unless mem_percent_str

      mem_percent_str.gsub('%', '').to_f
    end

    def parse_network_io(net_io_str)
      return { rx: 0, tx: 0 } unless net_io_str

      # Format: "1.23kB / 2.34kB"
      parts = net_io_str.split(' / ')

      {
        rx: parse_bytes(parts[0]),
        tx: parse_bytes(parts[1])
      }
    end

    def parse_bytes(byte_str)
      return 0 unless byte_str

      BYTE_MULTIPLIERS.each do |unit, multiplier|
        return byte_str.gsub(unit, '').to_f * multiplier if byte_str.include?(unit)
      end
      byte_str.to_f
    end

    def measure_response_time(url)
      start_time = Time.now
      response = make_http_request(url)
      return nil unless response&.code&.to_i == 200

      Time.now - start_time
    rescue StandardError
      nil
    end

    def make_http_request(url)
      uri = URI.parse(url)
      http = configure_http_client(uri)
      http.get(uri.path)
    end

    def configure_http_client(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.read_timeout = 5
      http.open_timeout = 5
      http
    end

    def calculate_system_averages(service_metrics, response_metrics)
      return {} if service_metrics.empty? && response_metrics.empty?

      {
        avg_cpu_percent: calculate_average(service_metrics, :cpu_percent),
        avg_memory_percent: calculate_average(service_metrics, :memory_percent),
        avg_response_time_ms: calculate_average(response_metrics, :response_time_ms)
      }
    end

    def calculate_average(metrics, key)
      values = metrics.values.map { |m| m[key] }.compact
      values.empty? ? 0.0 : (values.sum / values.size)
    end
  end
  # rubocop:enable Metrics/ClassLength
end
