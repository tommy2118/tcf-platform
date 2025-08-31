# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/monitoring/metrics_http_server'

RSpec.describe TcfPlatform::Monitoring::MetricsHttpServer do
  let(:server) { described_class.new }
  let(:monitoring_service) { instance_double(TcfPlatform::Monitoring::MonitoringService) }

  before do
    allow(TcfPlatform::Monitoring::MonitoringService).to receive(:new).and_return(monitoring_service)
  end

  describe '#initialize' do
    it 'initializes with default configuration' do
      expect(server.port).to eq(9091) # Default Prometheus port
      expect(server.host).to eq('0.0.0.0')
      expect(server.path).to eq('/metrics')
    end

    it 'supports custom configuration' do
      custom_server = described_class.new(
        port: 8080,
        host: 'localhost',
        path: '/custom-metrics'
      )
      
      aggregate_failures do
        expect(custom_server.port).to eq(8080)
        expect(custom_server.host).to eq('localhost')
        expect(custom_server.path).to eq('/custom-metrics')
      end
    end
  end

  describe '#start' do
    let(:webrick_server) { instance_double(WEBrick::HTTPServer) }

    before do
      allow(WEBrick::HTTPServer).to receive(:new).and_return(webrick_server)
      allow(webrick_server).to receive(:mount_proc)
      allow(webrick_server).to receive(:start)
      allow(Thread).to receive(:new).and_yield
    end

    it 'starts HTTP server on configured port' do
      server.start
      
      expect(WEBrick::HTTPServer).to have_received(:new).with(
        hash_including(Port: 9091, BindAddress: '0.0.0.0')
      )
      expect(webrick_server).to have_received(:start)
    end

    it 'mounts metrics endpoint at configured path' do
      server.start
      
      expect(webrick_server).to have_received(:mount_proc).with('/metrics', anything)
    end

    it 'runs server in background thread' do
      allow(Thread).to receive(:new).and_return(instance_double(Thread))
      
      server.start
      
      expect(Thread).to have_received(:new)
      expect(server.running?).to be true
    end

    it 'handles port already in use error' do
      allow(WEBrick::HTTPServer).to receive(:new).and_raise(Errno::EADDRINUSE)
      
      expect { server.start }.to raise_error(TcfPlatform::Monitoring::ServerStartupError, /Port 9091 is already in use/)
    end

    it 'prevents multiple server instances' do
      allow(server).to receive(:running?).and_return(true)
      
      expect { server.start }.to raise_error(StandardError, /already running/)
    end
  end

  describe '#stop' do
    let(:webrick_server) { instance_double(WEBrick::HTTPServer) }
    let(:server_thread) { instance_double(Thread) }

    before do
      allow(server).to receive(:webrick_server).and_return(webrick_server)
      allow(server).to receive(:server_thread).and_return(server_thread)
      allow(webrick_server).to receive(:shutdown)
      allow(server_thread).to receive(:kill)
      allow(server_thread).to receive(:join)
    end

    it 'gracefully shuts down HTTP server' do
      server.stop
      
      aggregate_failures do
        expect(webrick_server).to have_received(:shutdown)
        expect(server_thread).to have_received(:kill)
        expect(server_thread).to have_received(:join)
        expect(server.running?).to be false
      end
    end

    it 'handles stop when server not running' do
      allow(server).to receive(:running?).and_return(false)
      
      expect { server.stop }.not_to raise_error
    end
  end

  describe '#metrics_endpoint_handler' do
    let(:request) { instance_double(WEBrick::HTTPRequest) }
    let(:response) { instance_double(WEBrick::HTTPResponse) }
    let(:prometheus_metrics) do
      {
        status: 200,
        content_type: 'text/plain; version=0.0.4; charset=utf-8',
        body: "# HELP tcf_service_cpu_percent Service CPU usage\ntcf_service_cpu_percent{service=\"gateway\"} 45.2"
      }
    end

    before do
      allow(request).to receive(:request_method).and_return('GET')
      allow(response).to receive(:status=)
      allow(response).to receive(:content_type=)
      allow(response).to receive(:body=)
      allow(monitoring_service).to receive(:prometheus_metrics).and_return(prometheus_metrics)
    end

    it 'serves Prometheus metrics on GET request' do
      server.send(:metrics_endpoint_handler, request, response)
      
      aggregate_failures do
        expect(response).to have_received(:status=).with(200)
        expect(response).to have_received(:content_type=).with('text/plain; version=0.0.4; charset=utf-8')
        expect(response).to have_received(:body=).with(prometheus_metrics[:body])
        expect(monitoring_service).to have_received(:prometheus_metrics)
      end
    end

    it 'handles HEAD requests for monitoring probes' do
      allow(request).to receive(:request_method).and_return('HEAD')
      
      server.send(:metrics_endpoint_handler, request, response)
      
      aggregate_failures do
        expect(response).to have_received(:status=).with(200)
        expect(response).to have_received(:content_type=).with('text/plain; version=0.0.4; charset=utf-8')
        expect(response).to have_received(:body=).with('')
      end
    end

    it 'returns 405 for unsupported HTTP methods' do
      allow(request).to receive(:request_method).and_return('POST')
      
      server.send(:metrics_endpoint_handler, request, response)
      
      aggregate_failures do
        expect(response).to have_received(:status=).with(405)
        expect(response).to have_received(:body=).with('Method Not Allowed')
      end
    end

    it 'handles metrics collection errors gracefully' do
      allow(monitoring_service).to receive(:prometheus_metrics).and_raise(StandardError, 'Collection failed')
      
      server.send(:metrics_endpoint_handler, request, response)
      
      aggregate_failures do
        expect(response).to have_received(:status=).with(500)
        expect(response).to have_received(:content_type=).with('text/plain')
        expect(response).to have_received(:body=).with('# Error: Collection failed')
      end
    end

    it 'includes proper HTTP headers for Prometheus compatibility' do
      server.send(:metrics_endpoint_handler, request, response)
      
      # Verify content type matches Prometheus specification
      expect(response).to have_received(:content_type=).with('text/plain; version=0.0.4; charset=utf-8')
    end
  end

  describe '#health_endpoint_handler' do
    let(:request) { instance_double(WEBrick::HTTPRequest) }
    let(:response) { instance_double(WEBrick::HTTPResponse) }
    let(:health_status) do
      {
        status: 'healthy',
        components: {
          storage: { status: 'ok' },
          collector: { status: 'ok' }
        }
      }
    end

    before do
      allow(request).to receive(:request_method).and_return('GET')
      allow(response).to receive(:status=)
      allow(response).to receive(:content_type=)
      allow(response).to receive(:body=)
      allow(monitoring_service).to receive(:health_check).and_return(health_status)
    end

    it 'serves health check information' do
      server.send(:health_endpoint_handler, request, response)
      
      aggregate_failures do
        expect(response).to have_received(:status=).with(200)
        expect(response).to have_received(:content_type=).with('application/json')
        expect(monitoring_service).to have_received(:health_check)
      end
    end

    it 'returns 503 for unhealthy status' do
      unhealthy_status = health_status.merge(status: 'degraded')
      allow(monitoring_service).to receive(:health_check).and_return(unhealthy_status)
      
      server.send(:health_endpoint_handler, request, response)
      
      expect(response).to have_received(:status=).with(503)
    end
  end

  describe '#server_info_endpoint_handler' do
    let(:request) { instance_double(WEBrick::HTTPRequest) }
    let(:response) { instance_double(WEBrick::HTTPResponse) }

    before do
      allow(request).to receive(:request_method).and_return('GET')
      allow(response).to receive(:status=)
      allow(response).to receive(:content_type=)
      allow(response).to receive(:body=)
    end

    it 'provides server configuration and status information' do
      server.send(:server_info_endpoint_handler, request, response)
      
      expect(response).to have_received(:status=).with(200)
      expect(response).to have_received(:content_type=).with('application/json')
      expect(response).to have_received(:body=) do |body|
        info = JSON.parse(body)
        expect(info).to include('server_version')
        expect(info).to include('listening_port')
        expect(info).to include('metrics_path')
        expect(info).to include('uptime_seconds')
      end
    end
  end

  describe '#configure_security' do
    it 'supports basic authentication configuration' do
      server.configure_security(
        auth_type: 'basic',
        username: 'monitoring',
        password: 'secret123'
      )
      
      expect(server.auth_config).to include(
        auth_type: 'basic',
        username: 'monitoring'
      )
      expect(server.auth_config[:password]).not_to eq('secret123') # Should be hashed
    end

    it 'supports IP whitelist configuration' do
      allowed_ips = ['127.0.0.1', '10.0.0.0/8', '192.168.1.0/24']
      
      server.configure_security(
        auth_type: 'ip_whitelist',
        allowed_ips: allowed_ips
      )
      
      expect(server.auth_config[:allowed_ips]).to eq(allowed_ips)
    end

    it 'validates security configuration parameters' do
      expect { 
        server.configure_security(auth_type: 'invalid_type') 
      }.to raise_error(ArgumentError, /Unsupported auth_type/)
    end
  end

  describe '#request_logging' do
    let(:logger) { instance_double(Logger) }

    before do
      allow(server).to receive(:logger).and_return(logger)
      allow(logger).to receive(:info)
      allow(logger).to receive(:error)
    end

    it 'logs successful requests' do
      request = instance_double(WEBrick::HTTPRequest, 
        request_method: 'GET', 
        unparsed_uri: '/metrics',
        peeraddr: [nil, nil, nil, '127.0.0.1'],
        body: 'test data'
      )
      
      server.send(:log_request, request, 200, 1024)
      
      expect(logger).to have_received(:info).with(/GET \/metrics - 200 - \d+\.?\d* ms - 1024 bytes/)
    end

    it 'logs error requests with appropriate level' do
      request = instance_double(WEBrick::HTTPRequest, 
        request_method: 'POST', 
        unparsed_uri: '/metrics',
        peeraddr: [nil, nil, nil, '127.0.0.1'],
        body: 'error data'
      )
      
      server.send(:log_request, request, 405, 0)
      
      expect(logger).to have_received(:error).with(/POST \/metrics - 405 - \d+\.?\d* ms - 0 bytes/)
    end
  end

  describe '#performance_monitoring' do
    it 'tracks request metrics' do
      # Simulate several requests
      10.times { server.send(:record_request_metrics, 'GET', '/metrics', 200, 0.05) }
      
      metrics = server.request_metrics
      
      aggregate_failures do
        expect(metrics[:total_requests]).to eq(10)
        expect(metrics[:successful_requests]).to eq(10)
        expect(metrics[:avg_response_time_ms]).to be_within(1).of(50)
      end
    end

    it 'identifies slow requests' do
      # Record a slow request
      server.send(:record_request_metrics, 'GET', '/metrics', 200, 2.5)
      
      slow_requests = server.slow_requests_log
      
      expect(slow_requests).not_to be_empty
      expect(slow_requests.first[:duration_ms]).to eq(2500)
    end
  end

  describe '#graceful_shutdown' do
    it 'completes active requests before shutdown' do
      # Mock active connections
      allow(server).to receive(:active_connections).and_return(2)
      allow(server).to receive(:wait_for_connections_to_complete)
      
      server.graceful_shutdown(timeout: 5)
      
      expect(server).to have_received(:wait_for_connections_to_complete).with(5)
    end

    it 'forces shutdown after timeout' do
      allow(server).to receive(:active_connections).and_return(1)
      allow(server).to receive(:wait_for_connections_to_complete).and_return(false) # Timeout
      allow(server).to receive(:force_shutdown)
      
      server.graceful_shutdown(timeout: 1)
      
      expect(server).to have_received(:force_shutdown)
    end
  end
end