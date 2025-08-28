# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/monitoring_dashboard'
require_relative '../../lib/service_health_monitor'
require_relative '../../lib/metrics_collector'
require_relative '../../lib/alerting_system'

RSpec.describe TcfPlatform::MonitoringDashboard do
  let(:health_monitor) { instance_double(TcfPlatform::ServiceHealthMonitor) }
  let(:metrics_collector) { instance_double(TcfPlatform::MetricsCollector) }
  let(:alerting_system) { instance_double(TcfPlatform::AlertingSystem) }
  let(:dashboard) { described_class.new }

  before do
    allow(TcfPlatform::ServiceHealthMonitor).to receive(:new).and_return(health_monitor)
    allow(TcfPlatform::MetricsCollector).to receive(:new).and_return(metrics_collector)
    allow(TcfPlatform::AlertingSystem).to receive(:new).and_return(alerting_system)
    allow(alerting_system).to receive(:thresholds).and_return({})
  end

  describe '#initialize' do
    it 'initializes with all monitoring components' do
      dashboard # Force creation of the dashboard
      expect(TcfPlatform::ServiceHealthMonitor).to have_received(:new)
      expect(TcfPlatform::MetricsCollector).to have_received(:new)
      expect(TcfPlatform::AlertingSystem).to have_received(:new)
    end

    it 'supports custom refresh interval configuration' do
      dashboard = described_class.new(refresh_interval: 30)
      expect(dashboard.refresh_interval).to eq(30)
    end

    it 'uses default refresh interval of 10 seconds' do
      expect(dashboard.refresh_interval).to eq(10)
    end
  end

  describe '#collect_all_data' do
    let(:health_data) do
      {
        overall_status: 'healthy',
        healthy_count: 3,
        unhealthy_count: 0,
        services: {
          'tcf-gateway' => { status: 'running', health: 'healthy' },
          'tcf-personas' => { status: 'running', health: 'healthy' },
          'tcf-workflows' => { status: 'running', health: 'healthy' }
        },
        timestamp: Time.now
      }
    end

    let(:service_metrics) do
      {
        gateway: { cpu_percent: 45.2, memory_percent: 62.1, timestamp: Time.now },
        personas: { cpu_percent: 38.7, memory_percent: 58.9, timestamp: Time.now }
      }
    end

    let(:response_metrics) do
      {
        gateway: { response_time_ms: 250.0, status: 'responding', timestamp: Time.now },
        personas: { response_time_ms: 180.0, status: 'responding', timestamp: Time.now }
      }
    end

    let(:aggregated_metrics) do
      {
        gateway: {
          cpu_percent: 45.2,
          memory_percent: 62.1,
          response_time_ms: 250.0,
          status: 'responding'
        },
        system_averages: {
          avg_cpu_percent: 41.95,
          avg_memory_percent: 60.5,
          avg_response_time_ms: 215.0
        }
      }
    end

    let(:active_alerts) do
      [
        {
          service: 'gateway',
          metric: 'cpu_percent',
          level: 'warning',
          message: 'gateway CPU usage at 75.5% exceeds warning threshold of 70.0%'
        }
      ]
    end

    let(:health_endpoints) do
      {
        gateway: 'http://localhost:3000/health',
        personas: 'http://localhost:3001/health',
        workflows: 'http://localhost:3002/health'
      }
    end

    before do
      allow(health_monitor).to receive(:aggregate_health_status).and_return(health_data)
      allow(metrics_collector).to receive(:collect_service_metrics).and_return(service_metrics)
      allow(metrics_collector).to receive(:collect_response_time_metrics).and_return(response_metrics)
      allow(metrics_collector).to receive(:aggregate_metrics).and_return(aggregated_metrics)
      allow(alerting_system).to receive(:check_thresholds).and_return(active_alerts)
      allow(alerting_system).to receive(:active_alerts).and_return(active_alerts)
      allow(dashboard).to receive(:health_endpoints).and_return(health_endpoints)
    end

    it 'collects health status from all services' do
      result = dashboard.collect_all_data

      expect(health_monitor).to have_received(:aggregate_health_status)
      expect(result[:health]).to eq(health_data)
    end

    it 'collects performance metrics from all services' do
      result = dashboard.collect_all_data

      aggregate_failures do
        expect(metrics_collector).to have_received(:collect_service_metrics)
        expect(metrics_collector).to have_received(:collect_response_time_metrics).with(health_endpoints)
        expect(metrics_collector).to have_received(:aggregate_metrics).with(service_metrics, response_metrics)
        expect(result[:metrics]).to eq(aggregated_metrics)
      end
    end

    it 'checks alerting thresholds and includes active alerts' do
      result = dashboard.collect_all_data

      aggregate_failures do
        expect(alerting_system).to have_received(:check_thresholds).with(aggregated_metrics)
        expect(alerting_system).to have_received(:active_alerts)
        expect(result[:alerts]).to eq(active_alerts)
      end
    end

    it 'includes collection timestamp' do
      result = dashboard.collect_all_data
      
      expect(result[:collected_at]).to be_a(Time)
      expect(result[:collected_at]).to be_within(1).of(Time.now)
    end

    it 'returns comprehensive monitoring data structure' do
      result = dashboard.collect_all_data

      aggregate_failures do
        expect(result).to include(:health, :metrics, :alerts, :collected_at)
        expect(result[:health]).to be_a(Hash)
        expect(result[:metrics]).to be_a(Hash)
        expect(result[:alerts]).to be_an(Array)
        expect(result[:collected_at]).to be_a(Time)
      end
    end
  end

  describe '#dashboard_summary' do
    let(:dashboard_data) do
      {
        health: {
          overall_status: 'degraded',
          healthy_count: 2,
          unhealthy_count: 1,
          total_services: 3
        },
        metrics: {
          system_averages: {
            avg_cpu_percent: 65.3,
            avg_memory_percent: 78.9,
            avg_response_time_ms: 450.0
          }
        },
        alerts: [
          { level: 'warning', service: 'gateway' },
          { level: 'critical', service: 'personas' }
        ],
        collected_at: Time.now
      }
    end

    before do
      allow(dashboard).to receive(:collect_all_data).and_return(dashboard_data)
    end

    it 'provides high-level system status summary' do
      summary = dashboard.dashboard_summary

      aggregate_failures do
        expect(summary[:system_status]).to eq('degraded')
        expect(summary[:services_healthy]).to eq(2)
        expect(summary[:services_unhealthy]).to eq(1)
        expect(summary[:total_services]).to eq(3)
      end
    end

    it 'includes system-wide performance averages' do
      summary = dashboard.dashboard_summary

      aggregate_failures do
        expect(summary[:avg_cpu_usage]).to eq(65.3)
        expect(summary[:avg_memory_usage]).to eq(78.9)
        expect(summary[:avg_response_time]).to eq(450.0)
      end
    end

    it 'provides alert count breakdown by level' do
      summary = dashboard.dashboard_summary

      aggregate_failures do
        expect(summary[:total_alerts]).to eq(2)
        expect(summary[:warning_alerts]).to eq(1)
        expect(summary[:critical_alerts]).to eq(1)
      end
    end

    it 'includes summary timestamp' do
      summary = dashboard.dashboard_summary

      expect(summary[:timestamp]).to be_a(Time)
    end
  end

  describe '#service_details' do
    let(:service_name) { 'gateway' }
    let(:dashboard_data) do
      {
        health: {
          services: {
            'tcf-gateway' => { status: 'running', health: 'healthy', port: 3000 }
          }
        },
        metrics: {
          gateway: {
            cpu_percent: 45.2,
            memory_percent: 62.1,
            response_time_ms: 250.0,
            network_rx_bytes: 1024,
            network_tx_bytes: 2048
          }
        },
        alerts: [
          { service: 'gateway', level: 'warning', message: 'High CPU usage' }
        ]
      }
    end

    before do
      allow(dashboard).to receive(:collect_all_data).and_return(dashboard_data)
      allow(health_monitor).to receive(:service_uptime).with('gateway').and_return('2 hours 15 minutes')
    end

    it 'provides comprehensive service-specific information' do
      details = dashboard.service_details(service_name)

      aggregate_failures do
        expect(details[:service_name]).to eq('gateway')
        expect(details[:health_status]).to eq('healthy')
        expect(details[:container_status]).to eq('running')
        expect(details[:port]).to eq(3000)
      end
    end

    it 'includes current performance metrics' do
      details = dashboard.service_details(service_name)

      aggregate_failures do
        expect(details[:cpu_percent]).to eq(45.2)
        expect(details[:memory_percent]).to eq(62.1)
        expect(details[:response_time_ms]).to eq(250.0)
        expect(details[:network_rx_bytes]).to eq(1024)
        expect(details[:network_tx_bytes]).to eq(2048)
      end
    end

    it 'includes service uptime information' do
      details = dashboard.service_details(service_name)

      expect(health_monitor).to have_received(:service_uptime).with('gateway')
      expect(details[:uptime]).to eq('2 hours 15 minutes')
    end

    it 'includes service-specific alerts' do
      details = dashboard.service_details(service_name)

      aggregate_failures do
        expect(details[:alerts]).to be_an(Array)
        expect(details[:alerts].size).to eq(1)
        expect(details[:alerts].first[:level]).to eq('warning')
        expect(details[:alerts].first[:message]).to eq('High CPU usage')
      end
    end

    context 'when service has no current alerts' do
      let(:dashboard_data) do
        {
          health: { services: { 'tcf-gateway' => { status: 'running', health: 'healthy' } } },
          metrics: { gateway: { cpu_percent: 45.2 } },
          alerts: []
        }
      end

      it 'returns empty alerts array' do
        details = dashboard.service_details(service_name)
        expect(details[:alerts]).to be_empty
      end
    end

    context 'when service does not exist' do
      it 'returns nil for unknown service' do
        details = dashboard.service_details('unknown-service')
        expect(details).to be_nil
      end
    end
  end

  describe '#configure_alerting' do
    let(:threshold_config) do
      {
        cpu_percent: { warning: 70.0, critical: 90.0 },
        memory_percent: { warning: 80.0, critical: 95.0 }
      }
    end

    it 'configures alerting system thresholds' do
      allow(alerting_system).to receive(:configure_thresholds)

      dashboard.configure_alerting(threshold_config)

      expect(alerting_system).to have_received(:configure_thresholds).with(threshold_config)
    end

    it 'returns the configured thresholds' do
      allow(alerting_system).to receive(:configure_thresholds)
      allow(alerting_system).to receive(:thresholds).and_return(threshold_config)

      result = dashboard.configure_alerting(threshold_config)

      expect(result).to eq(threshold_config)
    end
  end

  describe '#start_monitoring' do
    it 'starts background monitoring with specified interval' do
      expect(dashboard).to respond_to(:start_monitoring)
    end

    it 'allows stopping background monitoring' do
      expect(dashboard).to respond_to(:stop_monitoring)
    end

    it 'tracks monitoring status' do
      expect(dashboard).to respond_to(:monitoring_active?)
    end
  end

  describe '#monitoring_history' do
    it 'maintains historical monitoring data' do
      expect(dashboard).to respond_to(:monitoring_history)
    end

    it 'supports configurable history size limit' do
      dashboard = described_class.new(max_history: 50)
      expect(dashboard.max_history).to eq(50)
    end
  end

  describe '#export_data' do
    let(:dashboard_data) { { health: {}, metrics: {}, alerts: [] } }

    before do
      allow(dashboard).to receive(:collect_all_data).and_return(dashboard_data)
    end

    it 'exports monitoring data as JSON' do
      json_data = dashboard.export_data('json')
      
      expect(json_data).to be_a(String)
      expect { JSON.parse(json_data) }.not_to raise_error
    end

    it 'exports monitoring data as CSV' do
      csv_data = dashboard.export_data('csv')
      
      expect(csv_data).to be_a(String)
      expect(csv_data).to include('service_name,status,cpu_percent,memory_percent')
    end

    it 'defaults to JSON format when no format specified' do
      json_data = dashboard.export_data
      
      expect(json_data).to be_a(String)
      expect { JSON.parse(json_data) }.not_to raise_error
    end

    it 'raises error for unsupported export format' do
      expect { dashboard.export_data('xml') }.to raise_error(ArgumentError, /Unsupported export format/)
    end
  end
end