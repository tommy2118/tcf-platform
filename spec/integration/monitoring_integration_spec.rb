# frozen_string_literal: true

require 'spec_helper'
require 'net/http'
require 'uri'

RSpec.describe 'TCF Platform Monitoring Integration', type: :integration do
  let(:monitoring_service) { TcfPlatform::Monitoring::MonitoringService.new }
  let(:cli) { TcfPlatform::CLI.new }

  before(:all) do
    # Skip integration tests if Docker isn't available or in CI
    skip 'Docker not available' unless system('which docker > /dev/null 2>&1')
    skip 'Integration tests disabled in CI' if ENV['CI']

    # Ensure Docker services are running for integration tests
    skip 'Unable to start required Docker services' unless system('docker-compose up -d redis postgres')
    sleep 5 # Allow services to start
  end

  after(:all) do
    system('docker-compose down')
  end

  describe 'End-to-End Monitoring Workflow' do
    it 'collects metrics from all running services' do
      # Start monitoring system
      monitoring_service.start

      # Wait for at least one collection cycle
      sleep(monitoring_service.collection_interval + 2)

      # Verify metrics were collected
      status = monitoring_service.status

      aggregate_failures do
        expect(status[:running]).to be true
        expect(status[:metrics_collected]).to be > 0
        expect(status[:last_collection]).to be_within(30).of(Time.now)
      end

      monitoring_service.stop
    end

    it 'stores metrics in time-series storage' do
      monitoring_service.start
      sleep(monitoring_service.collection_interval + 2)

      # Query stored metrics
      storage = TcfPlatform::Monitoring::TimeSeriesStorage.new
      query_result = storage.query_metrics({
                                             service: 'gateway',
                                             metric: 'cpu_percent',
                                             start_time: Time.now - 300,
                                             end_time: Time.now
                                           })

      expect(query_result).not_to be_empty
      expect(query_result.first).to include(:value, :timestamp)

      monitoring_service.stop
    end

    it 'provides Prometheus-compatible metrics endpoint' do
      monitoring_service.start
      monitoring_service.start_dashboard(port: 3010)

      sleep 2 # Allow dashboard to start

      # Test Prometheus scrape endpoint
      uri = URI('http://localhost:3010/metrics')
      response = Net::HTTP.get_response(uri)

      aggregate_failures do
        expect(response.code).to eq('200')
        expect(response.content_type).to include('text/plain')
        expect(response.body).to include('# HELP tcf_service')
        expect(response.body).to include('# TYPE tcf_service')
        expect(response.body).to match(/tcf_service_\w+\{service="[\w-]+"\} \d+\.?\d*/)
      end

      monitoring_service.stop_dashboard
      monitoring_service.stop
    end

    it 'CLI commands work with real monitoring system' do
      monitoring_service.start
      sleep(monitoring_service.collection_interval + 1)

      # Capture CLI output
      output = capture_stdout { cli.metrics_show }

      aggregate_failures do
        expect(output).to include('TCF Platform Metrics')
        expect(output).to include('CPU:')
        expect(output).to include('Memory:')
        expect(output).to include('%')
      end

      monitoring_service.stop
    end

    it 'handles service discovery and monitoring' do
      # Start some TCF services
      system('docker-compose up -d tcf-gateway tcf-personas')
      sleep 10 # Allow services to fully start

      monitoring_service.start
      sleep(monitoring_service.collection_interval + 2)

      status = monitoring_service.status

      # Should have discovered and monitored running services
      expect(status[:metrics_collected]).to be > 0

      monitoring_service.stop
      system('docker-compose stop tcf-gateway tcf-personas')
    end
  end

  describe 'Performance and Scalability' do
    it 'handles high-frequency metric collection efficiently' do
      # Configure for frequent collection
      high_freq_service = TcfPlatform::Monitoring::MonitoringService.new(
        collection_interval: 1 # 1 second
      )

      start_time = Time.now
      high_freq_service.start

      # Run for 10 seconds
      sleep 10

      status = high_freq_service.status
      execution_time = Time.now - start_time

      aggregate_failures do
        expect(status[:metrics_collected]).to be >= 8 # Should have at least 8 collections
        expect(execution_time).to be < 12 # Shouldn't take much longer than expected
      end

      high_freq_service.stop
    end

    it 'maintains performance under load' do
      monitoring_service.start

      # Simulate multiple concurrent metric queries
      threads = []
      10.times do
        threads << Thread.new do
          cli.metrics_show
          cli.metrics_query('gateway', 'cpu_percent')
        end
      end

      start_time = Time.now
      threads.each(&:join)
      execution_time = Time.now - start_time

      # All operations should complete quickly
      expect(execution_time).to be < 5

      monitoring_service.stop
    end
  end

  describe 'Error Handling and Recovery' do
    it 'recovers from temporary Redis outage' do
      monitoring_service.start

      # Simulate Redis outage
      system('docker-compose stop redis')
      sleep 2

      # Service should handle Redis being down
      expect(monitoring_service.running?).to be true

      # Restart Redis
      system('docker-compose start redis')
      sleep 5

      # Service should recover and continue collecting
      status = monitoring_service.status
      expect(status[:running]).to be true

      monitoring_service.stop
    end

    it 'handles Docker service failures gracefully' do
      monitoring_service.start

      # Stop a service that monitoring is watching
      system('docker-compose stop tcf-gateway')
      sleep(monitoring_service.collection_interval + 2)

      # Monitoring should continue despite service being down
      status = monitoring_service.status
      expect(status[:running]).to be true

      # Restart the service
      system('docker-compose start tcf-gateway')

      monitoring_service.stop
    end
  end

  describe 'Data Persistence and Retention' do
    it 'persists metrics data across monitoring service restarts' do
      # First session - collect some data
      monitoring_service.start
      sleep(monitoring_service.collection_interval + 2)
      monitoring_service.status
      monitoring_service.stop

      # Second session - should retain historical data
      TcfPlatform::Monitoring::MonitoringService.new
      storage = TcfPlatform::Monitoring::TimeSeriesStorage.new

      historical_data = storage.query_metrics({
                                                service: 'gateway',
                                                metric: 'cpu_percent',
                                                start_time: Time.now - 300,
                                                end_time: Time.now
                                              })

      expect(historical_data).not_to be_empty
    end

    it 'automatically cleans up expired metrics' do
      storage = TcfPlatform::Monitoring::TimeSeriesStorage.new

      # Store some test metrics with short TTL
      old_metric = {
        service: 'test',
        metric: 'test_metric',
        value: 100,
        timestamp: Time.now.to_i - 3600 # 1 hour ago
      }

      storage.store_metric(old_metric)

      # Force cleanup
      cleanup_stats = storage.cleanup_expired_metrics

      aggregate_failures do
        expect(cleanup_stats).to include(:scanned_keys)
        expect(cleanup_stats).to include(:deleted_keys)
        expect(cleanup_stats[:scanned_keys]).to be > 0
      end
    end
  end

  describe 'Dashboard Integration' do
    it 'serves monitoring dashboard with real data' do
      monitoring_service.start
      sleep(monitoring_service.collection_interval + 1)

      monitoring_service.start_dashboard(port: 3011)
      sleep 2

      # Test dashboard homepage
      uri = URI('http://localhost:3011/')
      response = Net::HTTP.get_response(uri)

      aggregate_failures do
        expect(response.code).to eq('200')
        expect(response.body).to include('TCF Platform Monitoring')
        expect(response.body).to include('Service Status')
      end

      # Test API endpoints
      api_uri = URI('http://localhost:3011/api/metrics/gateway')
      api_response = Net::HTTP.get_response(api_uri)

      aggregate_failures do
        expect(api_response.code).to eq('200')
        expect(api_response.content_type).to include('application/json')

        metrics_data = JSON.parse(api_response.body)
        expect(metrics_data).to include('cpu_percent')
        expect(metrics_data).to include('memory_percent')
      end

      monitoring_service.stop_dashboard
      monitoring_service.stop
    end
  end

  private

  def capture_stdout
    original_stdout = $stdout
    $stdout = fake = StringIO.new
    begin
      yield
    ensure
      $stdout = original_stdout
    end
    fake.string
  end
end
