# frozen_string_literal: true

require 'webrick'
require 'json'
require 'logger'
require 'digest'
require_relative 'monitoring_service'

module TcfPlatform
  module Monitoring
    # HTTP server for serving Prometheus metrics
    class MetricsHttpServer
      DEFAULT_CONFIG = {
        port: 9091,
        host: '0.0.0.0',
        path: '/metrics'
      }.freeze

      attr_reader :port, :host, :path, :auth_config

      def initialize(config = {})
        @config = DEFAULT_CONFIG.merge(config)
        @port = @config[:port]
        @host = @config[:host]
        @path = @config[:path]
        @running = false
        @webrick_server = nil
        @server_thread = nil
        @auth_config = {}
        @start_time = nil
        @request_stats = initialize_request_stats
        @logger = Logger.new($stdout)

        @monitoring_service = MonitoringService.new
      end

      def start
        raise StandardError, 'Server is already running' if @running

        begin
          configure_webrick_server
          mount_endpoints
          start_server_thread
          @running = true
          @start_time = Time.now
        rescue Errno::EADDRINUSE
          raise ServerStartupError, "Port #{@port} is already in use"
        end
      end

      def stop
        return unless @running

        @webrick_server&.shutdown
        @server_thread&.kill
        @server_thread&.join if @server_thread&.alive?
        
        @running = false
      end

      def running?
        @running
      end

      def configure_security(config)
        validate_auth_config!(config)
        
        @auth_config = config.dup
        
        # Hash password for basic auth
        if config[:auth_type] == 'basic' && config[:password]
          @auth_config[:password] = Digest::SHA256.hexdigest(config[:password])
        end
      end

      def request_metrics
        @request_stats.dup
      end

      def slow_requests_log
        @request_stats[:slow_requests] || []
      end

      def graceful_shutdown(timeout: 10)
        return unless @running

        # Wait for active connections to complete
        unless wait_for_connections_to_complete(timeout)
          force_shutdown
        else
          stop
        end
      end

      attr_reader :webrick_server, :server_thread

      private

      attr_reader :logger

      def configure_webrick_server
        @webrick_server = WEBrick::HTTPServer.new(
          Port: @port,
          BindAddress: @host,
          Logger: WEBrick::Log.new('/dev/null'),
          AccessLog: []
        )
      end

      def mount_endpoints
        # Main metrics endpoint
        @webrick_server.mount_proc(@path) do |request, response|
          start_time = Time.now
          
          begin
            metrics_endpoint_handler(request, response)
            duration_ms = (Time.now - start_time) * 1000
            log_request(request, response.status, duration_ms)
            record_request_metrics(request.request_method, @path, response.status, duration_ms / 1000.0)
          rescue StandardError => e
            logger.error("Error handling metrics request: #{e.message}")
            response.status = 500
            response.content_type = 'text/plain'
            response.body = "# Error: #{e.message}"
          end
        end

        # Health check endpoint
        @webrick_server.mount_proc('/health') do |request, response|
          health_endpoint_handler(request, response)
        end

        # Server info endpoint
        @webrick_server.mount_proc('/info') do |request, response|
          server_info_endpoint_handler(request, response)
        end
      end

      def start_server_thread
        @server_thread = Thread.new do
          @webrick_server.start
        end
      end

      def metrics_endpoint_handler(request, response)
        case request.request_method
        when 'GET'
          serve_metrics(response)
        when 'HEAD'
          response.status = 200
          response.content_type = 'text/plain; version=0.0.4; charset=utf-8'
          response.body = ''
        else
          response.status = 405
          response.body = 'Method Not Allowed'
        end
      end

      def serve_metrics(response)
        prometheus_data = @monitoring_service.prometheus_metrics

        response.status = prometheus_data[:status] || 200
        response.content_type = prometheus_data[:content_type] || 'text/plain; version=0.0.4; charset=utf-8'
        response.body = prometheus_data[:body]
      end

      def health_endpoint_handler(request, response)
        return unless request.request_method == 'GET'

        health_data = @monitoring_service.health_check
        
        response.status = health_data[:status] == 'healthy' ? 200 : 503
        response.content_type = 'application/json'
        response.body = JSON.pretty_generate(health_data)
      end

      def server_info_endpoint_handler(request, response)
        return unless request.request_method == 'GET'

        server_info = {
          server_version: TcfPlatform::VERSION,
          listening_port: @port,
          listening_host: @host,
          metrics_path: @path,
          uptime_seconds: @start_time ? (Time.now - @start_time).to_i : 0,
          request_count: @request_stats[:total_requests]
        }

        response.status = 200
        response.content_type = 'application/json'
        response.body = JSON.pretty_generate(server_info)
      end

      def log_request(request, status, duration_ms)
        remote_ip = request.peeraddr[3]
        log_level = status >= 400 ? :error : :info
        
        message = "#{request.request_method} #{request.unparsed_uri} - #{status} - #{duration_ms.round(2)} ms - #{request.body&.size || 0} bytes from #{remote_ip}"
        
        logger.send(log_level, message)
      end

      def record_request_metrics(method, path, status, duration_seconds)
        @request_stats[:total_requests] += 1
        @request_stats[:successful_requests] += 1 if status < 400
        
        # Track average response time
        total_time = @request_stats[:avg_response_time_ms] * (@request_stats[:total_requests] - 1)
        @request_stats[:avg_response_time_ms] = (total_time + duration_seconds * 1000) / @request_stats[:total_requests]

        # Track slow requests (>2 seconds)
        if duration_seconds > 2.0
          @request_stats[:slow_requests] ||= []
          @request_stats[:slow_requests] << {
            method: method,
            path: path,
            duration_ms: (duration_seconds * 1000).to_i,
            timestamp: Time.now
          }
          
          # Keep only last 10 slow requests
          @request_stats[:slow_requests] = @request_stats[:slow_requests].last(10)
        end
      end

      def validate_auth_config!(config)
        auth_type = config[:auth_type]
        
        unless %w[basic ip_whitelist].include?(auth_type)
          raise ArgumentError, "Unsupported auth_type: #{auth_type}"
        end

        case auth_type
        when 'basic'
          raise ArgumentError, 'Username required for basic auth' unless config[:username]
          raise ArgumentError, 'Password required for basic auth' unless config[:password]
        when 'ip_whitelist'
          raise ArgumentError, 'allowed_ips required for IP whitelist' unless config[:allowed_ips]
        end
      end

      def initialize_request_stats
        {
          total_requests: 0,
          successful_requests: 0,
          avg_response_time_ms: 0.0,
          slow_requests: []
        }
      end

      def active_connections
        # Mock implementation - in real server would track actual connections
        0
      end

      def wait_for_connections_to_complete(timeout_seconds)
        start_time = Time.now
        
        while active_connections > 0 && (Time.now - start_time) < timeout_seconds
          sleep 0.1
        end
        
        active_connections == 0
      end

      def force_shutdown
        @webrick_server&.shutdown
        @server_thread&.kill if @server_thread&.alive?
        @running = false
      end
    end
  end
end