# frozen_string_literal: true

require 'spec_helper'
require 'tcf_platform'
require_relative '../../lib/cli/platform_cli'

RSpec.describe TcfPlatform::CLI do
  subject(:cli) { described_class.new }

  let(:metrics_collector) { instance_double(TcfPlatform::MetricsCollector) }
  let(:prometheus_exporter) { instance_double(TcfPlatform::Monitoring::PrometheusExporter) }
  let(:time_series_storage) { instance_double(TcfPlatform::Monitoring::TimeSeriesStorage) }
  let(:monitoring_service) { instance_double(TcfPlatform::Monitoring::MonitoringService) }

  before do
    allow(TcfPlatform::MetricsCollector).to receive(:new).and_return(metrics_collector)
    allow(TcfPlatform::Monitoring::PrometheusExporter).to receive(:new).and_return(prometheus_exporter)
    allow(TcfPlatform::Monitoring::TimeSeriesStorage).to receive(:new).and_return(time_series_storage)
    allow(TcfPlatform::Monitoring::MonitoringService).to receive(:new).and_return(monitoring_service)
  end

  # Helper method to capture stdout
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

  describe '#metrics_show' do
    let(:current_metrics) do
      {
        gateway: {
          cpu_percent: 45.2,
          memory_percent: 62.1,
          memory_usage_mb: 128.5,
          response_time_ms: 250.0,
          status: 'healthy',
          timestamp: Time.now
        },
        personas: {
          cpu_percent: 38.7,
          memory_percent: 58.9,
          memory_usage_mb: 95.2,
          response_time_ms: 180.0,
          status: 'healthy',
          timestamp: Time.now
        }
      }
    end

    before do
      allow(metrics_collector).to receive(:collect_service_metrics).and_return(current_metrics)
    end

    it 'displays current metrics for all services' do
      output = capture_stdout { cli.metrics_show }

      aggregate_failures do
        expect(output).to include('TCF Platform Metrics')
        expect(output).to include('Gateway')
        expect(output).to include('Personas')
        expect(output).to include('CPU: 45.2%')
        expect(output).to include('Memory: 62.1%')
        expect(output).to include('Response Time: 250.0ms')
      end
    end

    it 'shows metrics for specific service when provided' do
      output = capture_stdout { cli.metrics_show('gateway') }

      aggregate_failures do
        expect(output).to include('Metrics for gateway')
        expect(output).to include('CPU: 45.2%')
        expect(output).to include('Memory: 62.1%')
        expect(output).not_to include('personas')
      end
    end

    it 'handles service not found gracefully' do
      output = capture_stdout { cli.metrics_show('nonexistent') }

      expect(output).to include('Service "nonexistent" not found')
    end

    it 'supports different output formats' do
      output = capture_stdout { cli.invoke(:metrics_show, [], { format: 'json' }) }

      expect { JSON.parse(output) }.not_to raise_error
    end

    it 'includes system health indicators' do
      output = capture_stdout { cli.metrics_show }

      aggregate_failures do
        expect(output).to include('System Status: ✅')
        expect(output).to include('Services Running: 2/2')
      end
    end

    context 'when metrics collection fails' do
      before do
        allow(metrics_collector).to receive(:collect_service_metrics).and_raise(StandardError, 'Collection failed')
      end

      it 'displays error message' do
        output = capture_stdout { cli.metrics_show }

        expect(output).to include('Error collecting metrics: Collection failed')
      end
    end
  end

  describe '#metrics_export' do
    let(:current_metrics) do
      {
        gateway: {
          cpu_percent: 45.2,
          memory_percent: 62.1,
          uptime_seconds: 86_400
        },
        personas: {
          cpu_percent: 23.8,
          memory_percent: 41.5,
          uptime_seconds: 86_400
        }
      }
    end

    let(:prometheus_output) do
      <<~PROMETHEUS
        # HELP tcf_service_cpu_percent Service CPU usage percentage
        # TYPE tcf_service_cpu_percent gauge
        tcf_service_cpu_percent{service="gateway"} 45.2 1693276800000
      PROMETHEUS
    end

    before do
      allow(metrics_collector).to receive(:collect_service_metrics).and_return(current_metrics)
      allow(prometheus_exporter).to receive(:generate_complete_export).with(any_args).and_return(prometheus_output)
    end

    it 'exports metrics in Prometheus format' do
      output = capture_stdout { cli.metrics_export }

      aggregate_failures do
        expect(output).to include('# HELP tcf_service_cpu_percent')
        expect(output).to include('tcf_service_cpu_percent{service="gateway"} 45.2')
        expect(prometheus_exporter).to have_received(:generate_complete_export).with(any_args)
      end
    end

    it 'supports file output' do
      output_file = '/tmp/metrics.txt'
      allow(File).to receive(:write)

      capture_stdout { cli.invoke(:metrics_export, [], { output: output_file }) }

      expect(File).to have_received(:write).with(output_file, prometheus_output)
    end

    it 'validates output file permissions' do
      readonly_file = '/tmp/readonly.txt'
      allow(File).to receive(:write).with(readonly_file, anything).and_raise(Errno::EACCES)

      output = capture_stdout { cli.invoke(:metrics_export, [], { output: readonly_file }) }

      expect(output).to include('Error writing to file')
    end
  end

  describe '#metrics_query' do
    let(:query_results) do
      [
        { value: 45.2, timestamp: 1_693_276_800 },
        { value: 47.8, timestamp: 1_693_277_100 },
        { value: 52.1, timestamp: 1_693_277_400 }
      ]
    end

    before do
      allow(time_series_storage).to receive(:query_metrics).and_return(query_results)
    end

    it 'queries historical metrics data' do
      output = capture_stdout { cli.metrics_query('gateway', 'cpu_percent') }

      aggregate_failures do
        expect(output).to include('Historical data for gateway cpu_percent')
        expect(output).to include('45.2')
        expect(output).to include('47.8')
        expect(output).to include('52.1')
        expect(time_series_storage).to have_received(:query_metrics)
      end
    end

    it 'supports time range filtering' do
      start_time = '2023-08-28T10:00:00Z'
      end_time = '2023-08-28T11:00:00Z'

      capture_stdout do
        cli.invoke(:metrics_query, %w[gateway cpu_percent], {
                     start_time: start_time,
                     end_time: end_time
                   })
      end

      expect(time_series_storage).to have_received(:query_metrics).with(
        hash_including(
          service: 'gateway',
          metric: 'cpu_percent'
        )
      )
    end

    it 'supports aggregation options' do
      capture_stdout do
        cli.invoke(:metrics_query, %w[gateway cpu_percent], {
                     aggregation: 'avg',
                     resolution: 300
                   })
      end

      expect(time_series_storage).to have_received(:query_metrics).with(
        hash_including(
          aggregation: 'avg',
          resolution: 300
        )
      )
    end

    it 'handles empty query results' do
      allow(time_series_storage).to receive(:query_metrics).and_return([])

      output = capture_stdout { cli.metrics_query('gateway', 'cpu_percent') }

      expect(output).to include('No data found')
    end
  end

  describe '#monitor_start' do
    it 'starts the monitoring system' do
      allow(monitoring_service).to receive(:start)
      allow(monitoring_service).to receive(:running?).and_return(false, true)

      output = capture_stdout { cli.monitor_start }

      aggregate_failures do
        expect(output).to include('📊 Starting monitoring system...')
        expect(output).to include('✅ Monitoring system started successfully')
        expect(monitoring_service).to have_received(:start)
      end
    end

    it 'handles already running monitoring system' do
      allow(monitoring_service).to receive(:running?).and_return(true)

      output = capture_stdout { cli.monitor_start }

      expect(output).to include('Monitoring system is already running')
    end

    it 'supports background mode' do
      allow(monitoring_service).to receive(:start)
      allow(monitoring_service).to receive(:running?).and_return(false, true)

      output = capture_stdout { cli.invoke(:monitor_start, [], { background: true }) }

      expect(output).to include('in background mode')
    end

    context 'when start fails' do
      before do
        allow(monitoring_service).to receive(:running?).and_return(false)
        allow(monitoring_service).to receive(:start).and_raise(StandardError, 'Failed to start')
      end

      it 'displays error message' do
        output = capture_stdout { cli.monitor_start }

        expect(output).to include('❌ Failed to start monitoring: Failed to start')
      end
    end
  end

  describe '#monitor_stop' do
    it 'stops the monitoring system' do
      allow(monitoring_service).to receive(:stop)
      allow(monitoring_service).to receive(:running?).and_return(true, false)

      output = capture_stdout { cli.monitor_stop }

      aggregate_failures do
        expect(output).to include('🛑 Stopping monitoring system...')
        expect(output).to include('✅ Monitoring system stopped successfully')
        expect(monitoring_service).to have_received(:stop)
      end
    end

    it 'handles already stopped monitoring system' do
      allow(monitoring_service).to receive(:running?).and_return(false)

      output = capture_stdout { cli.monitor_stop }

      expect(output).to include('Monitoring system is not running')
    end
  end

  describe '#monitor_status' do
    let(:monitoring_stats) do
      {
        running: true,
        uptime: 3600,
        metrics_collected: 15_420,
        last_collection: Time.now - 60,
        storage_size_mb: 45.2,
        errors_count: 3
      }
    end

    before do
      allow(monitoring_service).to receive(:status).and_return(monitoring_stats)
    end

    it 'displays comprehensive monitoring system status' do
      output = capture_stdout { cli.monitor_status }

      aggregate_failures do
        expect(output).to include('Monitoring System Status')
        expect(output).to include('Status: ✅ Running')
        expect(output).to include('Uptime: 1 hour')
        expect(output).to include('Metrics Collected: 15,420')
        expect(output).to include('Storage Size: 45.2 MB')
        expect(output).to include('Errors: 3')
      end
    end

    it 'shows detailed storage information' do
      allow(time_series_storage).to receive(:storage_statistics).and_return({
                                                                              used_memory_bytes: 47_185_920,
                                                                              total_keys: 5000,
                                                                              cache_hit_rate: 89.5
                                                                            })

      output = capture_stdout { cli.invoke(:monitor_status, [], { verbose: true }) }

      aggregate_failures do
        expect(output).to include('Storage Details')
        expect(output).to include('Used Memory: 45.0 MB')
        expect(output).to include('Total Keys: 5,000')
        expect(output).to include('Cache Hit Rate: 89.5%')
      end
    end
  end

  describe '#monitor_dashboard' do
    it 'starts monitoring dashboard server' do
      allow(monitoring_service).to receive(:start_dashboard).and_return({ url: 'http://localhost:3001' })
      allow(monitoring_service).to receive(:dashboard_url).and_return('http://localhost:3001')

      output = capture_stdout { cli.monitor_dashboard }

      aggregate_failures do
        expect(output).to include('🖥️  Starting monitoring dashboard...')
        expect(output).to include('Dashboard available at: http://localhost:3001')
        expect(monitoring_service).to have_received(:start_dashboard)
      end
    end

    it 'supports custom port configuration' do
      allow(monitoring_service).to receive(:start_dashboard)
      allow(monitoring_service).to receive(:dashboard_url).and_return('http://localhost:8080')

      capture_stdout { cli.invoke(:monitor_dashboard, [], { port: 8080 }) }

      expect(monitoring_service).to have_received(:start_dashboard).with(hash_including(port: 8080))
    end

    it 'handles dashboard startup failures' do
      allow(monitoring_service).to receive(:start_dashboard).and_raise(StandardError, 'Port already in use')

      output = capture_stdout { cli.monitor_dashboard }

      expect(output).to include('❌ Failed to start dashboard: Port already in use')
    end
  end

  describe '#metrics_history' do
    let(:history_data) do
      [
        {
          timestamp: Time.now - 300,
          services: {
            gateway: { cpu_percent: 45.2, memory_percent: 62.1 }
          }
        },
        {
          timestamp: Time.now - 600,
          services: {
            gateway: { cpu_percent: 43.1, memory_percent: 61.8 }
          }
        }
      ]
    end

    before do
      allow(metrics_collector).to receive(:metrics_history).and_return(history_data)
    end

    it 'displays historical metrics collection data' do
      output = capture_stdout { cli.metrics_history }

      aggregate_failures do
        expect(output).to include('Metrics Collection History')
        expect(output).to include('45.2%')
        expect(output).to include('43.1%')
      end
    end

    it 'supports limiting history results' do
      capture_stdout { cli.invoke(:metrics_history, [], { limit: 10 }) }

      # Should display limited results
      expect(output).not_to be_nil
    end

    it 'supports service-specific history' do
      output = capture_stdout { cli.invoke(:metrics_history, [], { service: 'gateway' }) }

      aggregate_failures do
        expect(output).to include('gateway')
        expect(output).to include('CPU: 45.2%')
      end
    end
  end

  describe '#monitor_cleanup' do
    let(:cleanup_stats) do
      {
        scanned_keys: 10_000,
        expired_keys: 500,
        deleted_keys: 500,
        cleanup_duration: 2.5,
        storage_freed_mb: 12.3
      }
    end

    before do
      allow(time_series_storage).to receive(:cleanup_expired_metrics).and_return(cleanup_stats)
    end

    it 'performs storage cleanup and shows statistics' do
      output = capture_stdout { cli.monitor_cleanup }

      aggregate_failures do
        expect(output).to include('🧹 Cleaning up expired metrics...')
        expect(output).to include('Scanned: 10,000 keys')
        expect(output).to include('Deleted: 500 expired keys')
        expect(output).to include('Freed: 12.3 MB')
        expect(output).to include('Duration: 2.5 seconds')
        expect(time_series_storage).to have_received(:cleanup_expired_metrics)
      end
    end

    it 'supports dry-run mode' do
      allow(time_series_storage).to receive(:cleanup_expired_metrics).with(dry_run: true).and_return(cleanup_stats)

      output = capture_stdout { cli.invoke(:monitor_cleanup, [], { dry_run: true }) }

      aggregate_failures do
        expect(output).to include('DRY RUN')
        expect(output).to include('Would delete: 500 expired keys')
      end
    end
  end
end
