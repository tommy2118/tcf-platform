# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/monitoring/monitoring_service'

RSpec.describe TcfPlatform::Monitoring::MonitoringService do
  let(:service) { described_class.new }
  let(:metrics_collector) { instance_double(TcfPlatform::MetricsCollector) }
  let(:time_series_storage) { instance_double(TcfPlatform::Monitoring::TimeSeriesStorage) }
  let(:prometheus_exporter) { instance_double(TcfPlatform::Monitoring::PrometheusExporter) }
  let(:dashboard_server) { instance_double(TcfPlatform::Monitoring::DashboardServer) }

  before do
    allow(TcfPlatform::MetricsCollector).to receive(:new).and_return(metrics_collector)
    allow(TcfPlatform::Monitoring::TimeSeriesStorage).to receive(:new).and_return(time_series_storage)
    allow(TcfPlatform::Monitoring::PrometheusExporter).to receive(:new).and_return(prometheus_exporter)
    allow(TcfPlatform::Monitoring::DashboardServer).to receive(:new).and_return(dashboard_server)
  end

  describe '#initialize' do
    it 'initializes all monitoring components' do
      service # Force initialization
      
      aggregate_failures do
        expect(TcfPlatform::MetricsCollector).to have_received(:new)
        expect(TcfPlatform::Monitoring::TimeSeriesStorage).to have_received(:new)
        expect(TcfPlatform::Monitoring::PrometheusExporter).to have_received(:new)
        expect(TcfPlatform::Monitoring::DashboardServer).to have_received(:new)
      end
    end

    it 'supports custom configuration' do
      config = { 
        collection_interval: 30,
        storage_config: { host: 'localhost', port: 6379 },
        dashboard_port: 3002
      }
      
      service = described_class.new(config)
      
      aggregate_failures do
        expect(service.collection_interval).to eq(30)
        expect(service.config).to include(config)
      end
    end

    it 'uses default configuration values' do
      expect(service.collection_interval).to eq(15) # Default 15 seconds
      expect(service.dashboard_port).to eq(3001) # Default port
    end
  end

  describe '#start' do
    it 'starts background metrics collection' do
      allow(service).to receive(:spawn_collection_thread)
      
      service.start
      
      aggregate_failures do
        expect(service).to have_received(:spawn_collection_thread)
        expect(service.running?).to be true
        expect(service.start_time).to be_a(Time)
      end
    end

    it 'validates storage connectivity before starting' do
      allow(time_series_storage).to receive(:ping).and_raise(Redis::CannotConnectError)
      
      expect { service.start }.to raise_error(TcfPlatform::Monitoring::ServiceStartupError)
    end

    it 'prevents multiple start attempts' do
      allow(service).to receive(:spawn_collection_thread)
      service.start # First start
      
      expect { service.start }.to raise_error(StandardError, /already running/)
    end

    it 'logs startup information' do
      allow(service).to receive(:spawn_collection_thread)
      logger = instance_double(Logger)
      allow(service).to receive(:logger).and_return(logger)
      allow(logger).to receive(:info)
      
      service.start
      
      expect(logger).to have_received(:info).with(/Monitoring service started/)
    end
  end

  describe '#stop' do
    before do
      allow(service).to receive(:spawn_collection_thread)
      service.start
    end

    it 'stops background metrics collection' do
      collection_thread = instance_double(Thread)
      allow(service).to receive(:collection_thread).and_return(collection_thread)
      allow(collection_thread).to receive(:kill)
      allow(collection_thread).to receive(:join)
      
      service.stop
      
      aggregate_failures do
        expect(collection_thread).to have_received(:kill)
        expect(collection_thread).to have_received(:join)
        expect(service.running?).to be false
      end
    end

    it 'stops dashboard server if running' do
      allow(dashboard_server).to receive(:running?).and_return(true)
      allow(dashboard_server).to receive(:stop)
      
      service.stop
      
      expect(dashboard_server).to have_received(:stop)
    end

    it 'handles stop when not running gracefully' do
      service.stop # First stop
      
      expect { service.stop }.not_to raise_error
    end

    it 'logs shutdown information' do
      logger = instance_double(Logger)
      allow(service).to receive(:logger).and_return(logger)
      allow(logger).to receive(:info)
      
      service.stop
      
      expect(logger).to have_received(:info).with(/Monitoring service stopped/)
    end
  end

  describe '#collect_and_store' do
    let(:service_metrics) do
      {
        gateway: { cpu_percent: 45.2, memory_percent: 62.1, timestamp: Time.now },
        personas: { cpu_percent: 38.7, memory_percent: 58.9, timestamp: Time.now }
      }
    end

    let(:system_metrics) do
      {
        system_load: 2.45,
        disk_usage_percent: 78.3,
        timestamp: Time.now
      }
    end

    before do
      allow(metrics_collector).to receive(:collect_service_metrics).and_return(service_metrics)
      allow(metrics_collector).to receive(:collect_system_metrics).and_return(system_metrics)
      allow(time_series_storage).to receive(:store_batch)
    end

    it 'collects metrics from all sources' do
      service.collect_and_store
      
      aggregate_failures do
        expect(metrics_collector).to have_received(:collect_service_metrics)
        expect(metrics_collector).to have_received(:collect_system_metrics)
      end
    end

    it 'stores collected metrics in batch for efficiency' do
      service.collect_and_store
      
      expect(time_series_storage).to have_received(:store_batch) do |metrics_batch|
        expect(metrics_batch).to be_an(Array)
        expect(metrics_batch.size).to be > 0
        # Should contain both service and system metrics
        service_metric = metrics_batch.find { |m| m[:service] == 'gateway' }
        system_metric = metrics_batch.find { |m| m[:metric] == 'system_load' }
        expect(service_metric).not_to be_nil
        expect(system_metric).not_to be_nil
      end
    end

    it 'includes collection timestamp for each metric' do
      collection_time = Time.now
      allow(Time).to receive(:now).and_return(collection_time)
      
      service.collect_and_store
      
      expect(time_series_storage).to have_received(:store_batch) do |metrics_batch|
        metrics_batch.each do |metric|
          expect(metric[:timestamp]).to eq(collection_time.to_i)
        end
      end
    end

    it 'handles collection errors gracefully without stopping service' do
      allow(metrics_collector).to receive(:collect_service_metrics).and_raise(StandardError, 'Collection failed')
      logger = instance_double(Logger)
      allow(service).to receive(:logger).and_return(logger)
      allow(logger).to receive(:error)
      
      expect { service.collect_and_store }.not_to raise_error
      expect(logger).to have_received(:error)
    end

    it 'tracks collection statistics' do
      service.collect_and_store
      
      stats = service.collection_stats
      aggregate_failures do
        expect(stats[:total_collections]).to eq(1)
        expect(stats[:last_collection_time]).to be_a(Time)
        expect(stats[:metrics_collected_count]).to be > 0
      end
    end
  end

  describe '#status' do
    before do
      allow(service).to receive(:spawn_collection_thread)
      service.start
    end

    it 'provides comprehensive service status' do
      allow(service).to receive(:uptime).and_return(3600)
      allow(service.collection_stats).to receive(:[]).with(:total_collections).and_return(240)
      allow(service.collection_stats).to receive(:[]).with(:errors_count).and_return(2)
      allow(time_series_storage).to receive(:storage_statistics).and_return({
        used_memory_bytes: 47_185_920,
        total_keys: 5000
      })
      
      status = service.status
      
      aggregate_failures do
        expect(status).to include(:running)
        expect(status).to include(:uptime)
        expect(status).to include(:metrics_collected)
        expect(status).to include(:errors_count)
        expect(status).to include(:storage_size_mb)
        expect(status[:running]).to be true
        expect(status[:uptime]).to eq(3600)
      end
    end

    it 'includes dashboard status when dashboard is running' do
      allow(dashboard_server).to receive(:running?).and_return(true)
      allow(dashboard_server).to receive(:url).and_return('http://localhost:3001')
      
      status = service.status
      
      aggregate_failures do
        expect(status[:dashboard_running]).to be true
        expect(status[:dashboard_url]).to eq('http://localhost:3001')
      end
    end
  end

  describe '#start_dashboard' do
    let(:dashboard_config) { { port: 3002, host: 'localhost' } }

    it 'starts monitoring dashboard server' do
      allow(dashboard_server).to receive(:start)
      allow(dashboard_server).to receive(:url).and_return('http://localhost:3002')
      
      result = service.start_dashboard(dashboard_config)
      
      aggregate_failures do
        expect(dashboard_server).to have_received(:start).with(dashboard_config)
        expect(result[:url]).to eq('http://localhost:3002')
        expect(result[:status]).to eq('started')
      end
    end

    it 'handles dashboard startup failures' do
      allow(dashboard_server).to receive(:start).and_raise(StandardError, 'Port already in use')
      
      expect { service.start_dashboard(dashboard_config) }.to raise_error(StandardError, /Port already in use/)
    end

    it 'prevents multiple dashboard instances' do
      allow(dashboard_server).to receive(:running?).and_return(true)
      
      expect { service.start_dashboard(dashboard_config) }.to raise_error(StandardError, /already running/)
    end
  end

  describe '#stop_dashboard' do
    it 'stops running dashboard server' do
      allow(dashboard_server).to receive(:running?).and_return(true)
      allow(dashboard_server).to receive(:stop)
      
      service.stop_dashboard
      
      expect(dashboard_server).to have_received(:stop)
    end

    it 'handles stop when dashboard not running' do
      allow(dashboard_server).to receive(:running?).and_return(false)
      
      expect { service.stop_dashboard }.not_to raise_error
    end
  end

  describe '#prometheus_metrics' do
    let(:prometheus_output) do
      <<~PROMETHEUS
        # HELP tcf_service_cpu_percent Service CPU usage percentage
        # TYPE tcf_service_cpu_percent gauge
        tcf_service_cpu_percent{service="gateway"} 45.2 1693276800000
      PROMETHEUS
    end

    before do
      allow(service).to receive(:collect_current_metrics).and_return({
        services: { gateway: { cpu_percent: 45.2 } },
        system: { system_load: 2.45 }
      })
      allow(prometheus_exporter).to receive(:generate_complete_export).and_return(prometheus_output)
    end

    it 'generates Prometheus-formatted metrics export' do
      result = service.prometheus_metrics
      
      aggregate_failures do
        expect(prometheus_exporter).to have_received(:generate_complete_export)
        expect(result[:content_type]).to eq('text/plain; version=0.0.4; charset=utf-8')
        expect(result[:body]).to include('tcf_service_cpu_percent')
      end
    end

    it 'handles export generation errors' do
      allow(prometheus_exporter).to receive(:generate_complete_export).and_raise(StandardError, 'Export failed')
      
      result = service.prometheus_metrics
      
      aggregate_failures do
        expect(result[:status]).to eq(500)
        expect(result[:body]).to include('Error generating metrics')
      end
    end
  end

  describe '#health_check' do
    it 'performs comprehensive health check of monitoring components' do
      allow(time_series_storage).to receive(:ping).and_return(true)
      allow(metrics_collector).to receive(:health_check).and_return({ status: 'ok' })
      allow(prometheus_exporter).to receive(:health_check).and_return({ status: 'ok' })
      
      health = service.health_check
      
      aggregate_failures do
        expect(health[:status]).to eq('healthy')
        expect(health[:components]).to include(:storage)
        expect(health[:components]).to include(:collector)
        expect(health[:components]).to include(:exporter)
        expect(health[:components][:storage][:status]).to eq('ok')
      end
    end

    it 'detects unhealthy components' do
      allow(time_series_storage).to receive(:ping).and_raise(Redis::TimeoutError)
      allow(metrics_collector).to receive(:health_check).and_return({ status: 'ok' })
      allow(prometheus_exporter).to receive(:health_check).and_return({ status: 'ok' })
      
      health = service.health_check
      
      aggregate_failures do
        expect(health[:status]).to eq('degraded')
        expect(health[:components][:storage][:status]).to eq('error')
        expect(health[:components][:storage][:error]).to include('Redis::TimeoutError')
      end
    end
  end

  describe '#restart' do
    before do
      allow(service).to receive(:spawn_collection_thread)
      service.start
    end

    it 'performs graceful restart of monitoring service' do
      allow(service).to receive(:stop)
      allow(service).to receive(:start)
      
      service.restart
      
      aggregate_failures do
        expect(service).to have_received(:stop)
        expect(service).to have_received(:start)
      end
    end

    it 'preserves configuration across restart' do
      original_config = service.config.dup
      
      service.restart
      
      expect(service.config).to eq(original_config)
    end
  end

  describe '#collection_thread_management' do
    it 'monitors collection thread health' do
      allow(service).to receive(:spawn_collection_thread)
      service.start
      
      # Simulate thread crash
      allow(service.collection_thread).to receive(:alive?).and_return(false)
      
      expect(service.collection_thread_healthy?).to be false
    end

    it 'automatically restarts crashed collection thread' do
      allow(service).to receive(:spawn_collection_thread)
      service.start
      
      original_thread = service.collection_thread
      allow(original_thread).to receive(:alive?).and_return(false)
      
      service.ensure_collection_thread_health
      
      expect(service.collection_thread).not_to eq(original_thread)
    end
  end
end