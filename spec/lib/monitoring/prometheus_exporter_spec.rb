# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/monitoring/prometheus_exporter'

RSpec.describe TcfPlatform::Monitoring::PrometheusExporter do
  # Stub Prometheus::Client::Registry for testing
  before(:all) do
    unless defined?(Prometheus::Client::Registry)
      module Prometheus
        module Client
          Registry = Class.new do
            attr_reader :metrics, :families

            def initialize
              @metrics = []
              @families = []
            end
          end
        end
      end
    end
  end

  let(:exporter) { described_class.new }

  describe '#initialize' do
    it 'initializes with default configuration' do
      expect(exporter).to be_an_instance_of(described_class)
      expect(exporter.registry).to be_a(Prometheus::Client::Registry)
    end

    it 'supports custom registry configuration' do
      custom_registry = instance_double(Prometheus::Client::Registry)
      exporter = described_class.new(registry: custom_registry)

      expect(exporter.registry).to eq(custom_registry)
    end
  end

  describe '#export_service_metrics' do
    let(:service_metrics) do
      {
        gateway: {
          cpu_percent: 45.2,
          memory_percent: 62.1,
          memory_usage_mb: 128.5,
          response_time_ms: 250.0,
          network_rx_bytes: 1024,
          network_tx_bytes: 2048,
          timestamp: Time.now
        },
        personas: {
          cpu_percent: 38.7,
          memory_percent: 58.9,
          memory_usage_mb: 95.2,
          response_time_ms: 180.0,
          network_rx_bytes: 856,
          network_tx_bytes: 1450,
          timestamp: Time.now
        }
      }
    end

    it 'exports CPU metrics in Prometheus format' do
      prometheus_output = exporter.export_service_metrics(service_metrics)

      aggregate_failures do
        expect(prometheus_output).to include('tcf_service_cpu_percent{service="gateway"} 45.2')
        expect(prometheus_output).to include('tcf_service_cpu_percent{service="personas"} 38.7')
        expect(prometheus_output).to include('# TYPE tcf_service_cpu_percent gauge')
        expect(prometheus_output).to include('# HELP tcf_service_cpu_percent Service CPU usage percentage')
      end
    end

    it 'exports memory metrics in Prometheus format' do
      prometheus_output = exporter.export_service_metrics(service_metrics)

      aggregate_failures do
        expect(prometheus_output).to include('tcf_service_memory_percent{service="gateway"} 62.1')
        expect(prometheus_output).to include('tcf_service_memory_usage_bytes{service="gateway"} 134742016')
        expect(prometheus_output).to include('# TYPE tcf_service_memory_percent gauge')
        expect(prometheus_output).to include('# TYPE tcf_service_memory_usage_bytes gauge')
      end
    end

    it 'exports response time metrics in Prometheus format' do
      prometheus_output = exporter.export_service_metrics(service_metrics)

      aggregate_failures do
        expect(prometheus_output).to include('tcf_service_response_time_seconds{service="gateway"} 0.25')
        expect(prometheus_output).to include('tcf_service_response_time_seconds{service="personas"} 0.18')
        expect(prometheus_output).to include('# TYPE tcf_service_response_time_seconds gauge')
        expect(prometheus_output).to include('# HELP tcf_service_response_time_seconds Service HTTP response time')
      end
    end

    it 'exports network I/O metrics in Prometheus format' do
      prometheus_output = exporter.export_service_metrics(service_metrics)

      aggregate_failures do
        expect(prometheus_output).to include('tcf_service_network_rx_bytes{service="gateway"} 1024')
        expect(prometheus_output).to include('tcf_service_network_tx_bytes{service="gateway"} 2048')
        expect(prometheus_output).to include('# TYPE tcf_service_network_rx_bytes counter')
        expect(prometheus_output).to include('# TYPE tcf_service_network_tx_bytes counter')
      end
    end

    it 'includes metric timestamps' do
      allow(Time).to receive(:now).and_return(Time.at(1_693_276_800)) # Fixed timestamp
      prometheus_output = exporter.export_service_metrics(service_metrics)

      expect(prometheus_output).to include('tcf_service_cpu_percent{service="gateway"} 45.2 1693276800000')
    end

    it 'handles empty metrics gracefully' do
      prometheus_output = exporter.export_service_metrics({})

      expect(prometheus_output).to be_a(String)
      expect(prometheus_output).to include('# Prometheus metrics for TCF Platform')
    end

    it 'validates metric names comply with Prometheus naming conventions' do
      prometheus_output = exporter.export_service_metrics(service_metrics)

      # Check that all metric names follow prometheus naming convention (snake_case, no special chars)
      metric_lines = prometheus_output.split("\n").grep(/^tcf_/)
      metric_lines.each do |line|
        metric_name = line.split('{').first.split.first
        expect(metric_name).to match(/^[a-zA-Z_:][a-zA-Z0-9_:]*$/)
      end
    end
  end

  describe '#export_system_metrics' do
    let(:system_metrics) do
      {
        system_load: 2.45,
        disk_usage_percent: 78.3,
        disk_available_bytes: 50_000_000_000,
        uptime_seconds: 86_400,
        timestamp: Time.now
      }
    end

    it 'exports system-wide metrics in Prometheus format' do
      prometheus_output = exporter.export_system_metrics(system_metrics)

      aggregate_failures do
        expect(prometheus_output).to include('tcf_system_load 2.45')
        expect(prometheus_output).to include('tcf_disk_usage_percent 78.3')
        expect(prometheus_output).to include('tcf_disk_available_bytes 50000000000')
        expect(prometheus_output).to include('tcf_system_uptime_seconds 86400')
        expect(prometheus_output).to include('# TYPE tcf_system_load gauge')
      end
    end
  end

  describe '#export_custom_metrics' do
    let(:custom_metrics) do
      {
        'backup_job_duration_seconds' => { value: 120.5, type: 'gauge' },
        'total_api_requests' => { value: 15_432, type: 'counter' },
        'active_user_sessions' => { value: 89, type: 'gauge' }
      }
    end

    it 'exports custom application metrics' do
      prometheus_output = exporter.export_custom_metrics(custom_metrics)

      aggregate_failures do
        expect(prometheus_output).to include('tcf_backup_job_duration_seconds 120.5')
        expect(prometheus_output).to include('tcf_total_api_requests 15432')
        expect(prometheus_output).to include('tcf_active_user_sessions 89')
        expect(prometheus_output).to include('# TYPE tcf_backup_job_duration_seconds gauge')
        expect(prometheus_output).to include('# TYPE tcf_total_api_requests counter')
      end
    end

    it 'validates metric types are supported' do
      invalid_metrics = { 'test_metric' => { value: 100, type: 'unsupported_type' } }

      expect { exporter.export_custom_metrics(invalid_metrics) }.to raise_error(ArgumentError, /Unsupported metric type/)
    end
  end

  describe '#generate_complete_export' do
    let(:all_metrics_data) do
      {
        services: {
          gateway: { cpu_percent: 45.2, memory_percent: 62.1, timestamp: Time.now }
        },
        system: {
          system_load: 2.45,
          uptime_seconds: 86_400,
          timestamp: Time.now
        },
        custom: {
          'backup_success_total' => { value: 42, type: 'counter' }
        }
      }
    end

    it 'generates complete Prometheus export with all metric types' do
      prometheus_output = exporter.generate_complete_export(all_metrics_data)

      aggregate_failures do
        expect(prometheus_output).to include('# Prometheus metrics for TCF Platform')
        expect(prometheus_output).to include('tcf_service_cpu_percent{service="gateway"} 45.2')
        expect(prometheus_output).to include('tcf_system_load 2.45')
        expect(prometheus_output).to include('tcf_backup_success_total 42')
        expect(prometheus_output).to include('# Generated at:')
      end
    end

    it 'includes metadata about the export' do
      prometheus_output = exporter.generate_complete_export(all_metrics_data)

      aggregate_failures do
        expect(prometheus_output).to include('# Exporter: TCF Platform Prometheus Exporter')
        expect(prometheus_output).to include('# Version:')
        expect(prometheus_output).to include('# Generated at:')
      end
    end
  end

  describe '#scrape_endpoint' do
    it 'provides HTTP endpoint compatible with Prometheus scraping' do
      expect(exporter).to respond_to(:scrape_endpoint)
    end

    it 'returns content-type appropriate for Prometheus' do
      allow(exporter).to receive(:collect_all_metrics).and_return({})
      response = exporter.scrape_endpoint

      expect(response[:content_type]).to eq('text/plain; version=0.0.4; charset=utf-8')
    end

    it 'handles scraping errors gracefully' do
      allow(exporter).to receive(:collect_all_metrics).and_raise(StandardError, 'Collection failed')
      response = exporter.scrape_endpoint

      aggregate_failures do
        expect(response[:status]).to eq(500)
        expect(response[:body]).to include('# Error collecting metrics')
      end
    end
  end

  describe '#configure_metric_labels' do
    it 'allows configuration of additional metric labels' do
      labels = { environment: 'production', region: 'us-west-2' }
      exporter.configure_metric_labels(labels)

      expect(exporter.metric_labels).to include(labels)
    end

    it 'validates label names comply with Prometheus requirements' do
      invalid_labels = { '123invalid' => 'value', 'invalid-name' => 'value' }

      expect { exporter.configure_metric_labels(invalid_labels) }.to raise_error(ArgumentError, /Invalid label name/)
    end
  end

  describe '#metric_registry_stats' do
    it 'provides statistics about registered metrics' do
      # Register some test metrics first
      allow(exporter).to receive(:export_service_metrics).and_return('test metrics')
      exporter.export_service_metrics({ gateway: { cpu_percent: 50.0 } })

      stats = exporter.metric_registry_stats

      aggregate_failures do
        expect(stats).to include(:total_metrics)
        expect(stats).to include(:metric_families)
        expect(stats).to include(:last_export_time)
        expect(stats[:total_metrics]).to be_a(Integer)
      end
    end
  end
end
