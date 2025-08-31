# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/monitoring/enhanced_metrics_collector'

RSpec.describe TcfPlatform::Monitoring::EnhancedMetricsCollector do
  let(:collector) { described_class.new }
  let(:docker_manager) { instance_double(TcfPlatform::DockerManager) }
  let(:service_registry) { instance_double(TcfPlatform::ServiceRegistry) }

  before do
    allow(TcfPlatform::DockerManager).to receive(:new).and_return(docker_manager)
    allow(TcfPlatform::ServiceRegistry).to receive(:new).and_return(service_registry)
  end

  describe '#initialize' do
    it 'initializes with enhanced configuration options' do
      config = {
        collection_timeout: 30,
        retry_attempts: 3,
        metrics_cache_ttl: 60
      }
      
      collector = described_class.new(config)
      
      aggregate_failures do
        expect(collector.collection_timeout).to eq(30)
        expect(collector.retry_attempts).to eq(3)
        expect(collector.metrics_cache_ttl).to eq(60)
      end
    end

    it 'uses sensible defaults when no config provided' do
      aggregate_failures do
        expect(collector.collection_timeout).to eq(10)
        expect(collector.retry_attempts).to eq(2)
        expect(collector.metrics_cache_ttl).to eq(30)
      end
    end
  end

  describe '#collect_comprehensive_metrics' do
    let(:service_status) do
      {
        'tcf-gateway' => { status: 'running', health: 'healthy' },
        'tcf-personas' => { status: 'running', health: 'healthy' },
        'tcf-workflows' => { status: 'stopped', health: 'unknown' }
      }
    end

    let(:docker_stats) do
      {
        'tcf-gateway-1' => {
          'CPUPerc' => '2.45%',
          'MemUsage' => '128.5MiB / 1.952GiB',
          'MemPerc' => '6.43%',
          'NetIO' => '1.23kB / 2.34kB',
          'BlockIO' => '4.56MB / 1.23MB',
          'PIDs' => '25'
        },
        'tcf-personas-1' => {
          'CPUPerc' => '1.20%',
          'MemUsage' => '95.2MiB / 1.952GiB',
          'MemPerc' => '4.76%',
          'NetIO' => '856B / 1.45kB',
          'BlockIO' => '2.34MB / 890kB',
          'PIDs' => '18'
        }
      }
    end

    before do
      allow(docker_manager).to receive(:service_status).and_return(service_status)
      allow(docker_manager).to receive(:service_stats).and_return(docker_stats)
    end

    it 'collects enhanced container metrics including PIDs and disk I/O' do
      metrics = collector.collect_comprehensive_metrics
      
      aggregate_failures do
        expect(metrics[:services][:gateway]).to include(
          cpu_percent: 2.45,
          memory_percent: 6.43,
          memory_usage_mb: be_within(0.1).of(128.5),
          network_rx_bytes: be_a(Integer),
          network_tx_bytes: be_a(Integer),
          disk_read_bytes: be_a(Integer),
          disk_write_bytes: be_a(Integer),
          process_count: 25
        )
        
        expect(metrics[:services][:personas]).to include(
          cpu_percent: 1.20,
          memory_percent: 4.76,
          process_count: 18
        )
      end
    end

    it 'includes service health status in metrics' do
      metrics = collector.collect_comprehensive_metrics
      
      aggregate_failures do
        expect(metrics[:services][:gateway][:health_status]).to eq('healthy')
        expect(metrics[:services][:personas][:health_status]).to eq('healthy')
        expect(metrics[:services][:workflows][:health_status]).to eq('unknown')
      end
    end

    it 'collects system-wide metrics' do
      allow(collector).to receive(:collect_system_load).and_return(2.45)
      allow(collector).to receive(:collect_disk_metrics).and_return({
        usage_percent: 78.3,
        available_bytes: 50_000_000_000,
        total_bytes: 200_000_000_000
      })
      allow(collector).to receive(:collect_network_metrics).and_return({
        interfaces: {
          'eth0' => { rx_bytes: 1_000_000, tx_bytes: 2_000_000 }
        }
      })
      
      metrics = collector.collect_comprehensive_metrics
      
      aggregate_failures do
        expect(metrics[:system]).to include(
          load_average: 2.45,
          disk_usage_percent: 78.3,
          disk_available_bytes: 50_000_000_000,
          network_interfaces: be_a(Hash)
        )
      end
    end

    it 'includes collection metadata' do
      metrics = collector.collect_comprehensive_metrics
      
      aggregate_failures do
        expect(metrics[:metadata]).to include(
          :collection_timestamp,
          :collection_duration_ms,
          :total_services_discovered,
          :healthy_services_count,
          :unhealthy_services_count
        )
        expect(metrics[:metadata][:collection_timestamp]).to be_a(Time)
      end
    end
  end

  describe '#collect_application_metrics' do
    it 'collects custom application metrics from services' do
      allow(collector).to receive(:fetch_service_metrics).with('gateway', '/metrics').and_return({
        'http_requests_total' => 15432,
        'http_request_duration_seconds_avg' => 0.145,
        'active_connections' => 25
      })
      
      app_metrics = collector.collect_application_metrics('gateway')
      
      aggregate_failures do
        expect(app_metrics).to include(
          http_requests_total: 15432,
          avg_response_time_seconds: 0.145,
          active_connections: 25
        )
      end
    end

    it 'handles services without custom metrics endpoints' do
      allow(collector).to receive(:fetch_service_metrics).and_raise(Net::HTTPError.new('Not Found', nil))
      
      app_metrics = collector.collect_application_metrics('personas')
      
      expect(app_metrics).to eq({ custom_metrics_available: false })
    end
  end

  describe '#collect_with_retries' do
    it 'retries failed collections based on configuration' do
      call_count = 0
      allow(docker_manager).to receive(:service_stats) do
        call_count += 1
        if call_count <= 2
          raise StandardError, 'Connection failed'
        else
          {}
        end
      end
      
      expect { collector.collect_with_retries { docker_manager.service_stats } }.not_to raise_error
      expect(docker_manager).to have_received(:service_stats).exactly(3).times
    end

    it 'raises error after exhausting retry attempts' do
      allow(docker_manager).to receive(:service_stats).and_raise(StandardError, 'Persistent failure')
      
      expect { 
        collector.collect_with_retries { docker_manager.service_stats }
      }.to raise_error(TcfPlatform::Monitoring::CollectionError, /Persistent failure/)
    end

    it 'includes retry information in error details' do
      allow(docker_manager).to receive(:service_stats).and_raise(StandardError, 'Persistent failure')
      
      begin
        collector.collect_with_retries { docker_manager.service_stats }
      rescue TcfPlatform::Monitoring::CollectionError => e
        expect(e.retry_count).to eq(2)
        expect(e.original_error).to be_a(StandardError)
      end
    end
  end

  describe '#metrics_caching' do
    it 'caches metrics to reduce collection overhead' do
      allow(docker_manager).to receive(:service_status).and_return({}).once
      allow(docker_manager).to receive(:service_stats).and_return({}).once
      
      # First call should hit Docker
      collector.collect_comprehensive_metrics
      
      # Second call should use cache
      cached_metrics = collector.collect_comprehensive_metrics
      
      expect(cached_metrics[:metadata][:from_cache]).to be true
    end

    it 'respects cache TTL configuration' do
      collector = described_class.new(metrics_cache_ttl: 1) # 1 second TTL
      allow(docker_manager).to receive(:service_status).and_return({})
      allow(docker_manager).to receive(:service_stats).and_return({})
      
      # First call
      collector.collect_comprehensive_metrics
      
      # Wait for cache to expire
      sleep 2
      
      # Should call Docker again
      collector.collect_comprehensive_metrics
      
      expect(docker_manager).to have_received(:service_stats).twice
    end

    it 'allows bypassing cache when needed' do
      allow(docker_manager).to receive(:service_status).and_return({})
      allow(docker_manager).to receive(:service_stats).and_return({})
      
      collector.collect_comprehensive_metrics # Prime cache
      fresh_metrics = collector.collect_comprehensive_metrics(bypass_cache: true)
      
      expect(fresh_metrics[:metadata][:from_cache]).to be false
      expect(docker_manager).to have_received(:service_stats).twice
    end
  end

  describe '#collect_historical_trends' do
    it 'calculates performance trends over time' do
      # Simulate historical data
      allow(collector).to receive(:metrics_history).and_return([
        { timestamp: Time.now - 300, services: { gateway: { cpu_percent: 40.0 } } },
        { timestamp: Time.now - 240, services: { gateway: { cpu_percent: 45.0 } } },
        { timestamp: Time.now - 180, services: { gateway: { cpu_percent: 50.0 } } },
        { timestamp: Time.now - 120, services: { gateway: { cpu_percent: 52.0 } } },
        { timestamp: Time.now - 60, services: { gateway: { cpu_percent: 48.0 } } }
      ])
      
      trends = collector.collect_historical_trends('gateway', 'cpu_percent', 300)
      
      aggregate_failures do
        expect(trends).to include(:trend_direction) # 'increasing', 'decreasing', 'stable'
        expect(trends).to include(:average_change_per_minute)
        expect(trends).to include(:volatility_score)
        expect(trends).to include(:prediction_next_5min)
      end
    end

    it 'identifies anomalies in metric patterns' do
      # Simulate data with anomaly (using symbols for service and metric keys)
      anomalous_data = [
        { timestamp: Time.now - 300, services: { gateway: { cpu_percent: 45.0 } } },
        { timestamp: Time.now - 240, services: { gateway: { cpu_percent: 47.0 } } },
        { timestamp: Time.now - 180, services: { gateway: { cpu_percent: 95.0 } } }, # Anomaly
        { timestamp: Time.now - 120, services: { gateway: { cpu_percent: 46.0 } } },
        { timestamp: Time.now - 60, services: { gateway: { cpu_percent: 48.0 } } }
      ]
      
      allow(collector).to receive(:metrics_history).and_return(anomalous_data)
      
      anomalies = collector.detect_metric_anomalies('gateway', 'cpu_percent', 300)
      
      aggregate_failures do
        expect(anomalies).not_to be_empty
        expect(anomalies.first[:timestamp]).to be_within(1).of(Time.now - 180)
        expect(anomalies.first[:value]).to eq(95.0)
        expect(anomalies.first[:anomaly_score]).to be > 0.8
      end
    end
  end

  describe '#health_scoring' do
    let(:service_metrics) do
      {
        cpu_percent: 75.0,
        memory_percent: 85.0,
        response_time_ms: 500.0,
        error_rate_percent: 2.5,
        disk_usage_percent: 60.0
      }
    end

    it 'calculates comprehensive health score for services' do
      health_score = collector.calculate_service_health_score('gateway', service_metrics)
      
      aggregate_failures do
        expect(health_score).to include(:overall_score) # 0-100
        expect(health_score).to include(:component_scores)
        expect(health_score[:component_scores]).to include(:cpu, :memory, :response_time, :error_rate)
        expect(health_score[:overall_score]).to be_between(0, 100)
      end
    end

    it 'provides health recommendations' do
      health_analysis = collector.analyze_service_health('gateway', service_metrics)
      
      aggregate_failures do
        expect(health_analysis).to include(:health_status) # 'excellent', 'good', 'warning', 'critical'
        expect(health_analysis).to include(:recommendations)
        expect(health_analysis[:recommendations]).to be_an(Array)
      end
    end

    it 'identifies services at risk' do
      risky_metrics = {
        cpu_percent: 95.0,
        memory_percent: 98.0,
        response_time_ms: 2000.0,
        error_rate_percent: 15.0
      }
      
      health_analysis = collector.analyze_service_health('gateway', risky_metrics)
      
      aggregate_failures do
        expect(health_analysis[:health_status]).to eq('critical')
        expect(health_analysis[:at_risk_factors]).to include('cpu', 'memory', 'response_time', 'error_rate')
        expect(health_analysis[:recommendations]).to include(match(/immediate attention/i))
      end
    end
  end

  describe '#export_metrics_batch' do
    it 'efficiently exports large metric datasets' do
      large_dataset = {
        services: Hash.new { |h, k| h[k] = { cpu_percent: rand(0..100), memory_percent: rand(0..100) } },
        system: { load_average: 2.5 },
        metadata: { collection_timestamp: Time.now }
      }
      
      # Populate with many services
      50.times { |i| large_dataset[:services]["service_#{i}"] }
      
      exported_batch = collector.export_metrics_batch(large_dataset)
      
      aggregate_failures do
        expect(exported_batch).to be_an(Array)
        expect(exported_batch.length).to be > 50 # Should have metrics for all services plus system
        expect(exported_batch.first).to include(:service, :metric, :value, :timestamp)
      end
    end

    it 'handles export errors gracefully' do
      corrupted_data = { invalid: 'data structure' }
      
      expect { 
        collector.export_metrics_batch(corrupted_data) 
      }.to raise_error(TcfPlatform::Monitoring::ExportError)
    end
  end
end