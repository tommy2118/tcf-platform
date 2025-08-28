# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/metrics_collector'

RSpec.describe TcfPlatform::MetricsCollector do
  let(:collector) { described_class.new }

  describe '#collect_service_metrics' do
    context 'when collecting Docker container metrics' do
      before do
        allow(collector).to receive(:docker_stats_output).and_return({
                                                                       'tcf-gateway-1' => {
                                                                         'CPUPerc' => '2.45%',
                                                                         'MemUsage' => '128.5MiB / 1.952GiB',
                                                                         'MemPerc' => '6.43%',
                                                                         'NetIO' => '1.23kB / 2.34kB',
                                                                         'BlockIO' => '4.56MB / 1.23MB'
                                                                       },
                                                                       'tcf-personas-1' => {
                                                                         'CPUPerc' => '1.20%',
                                                                         'MemUsage' => '95.2MiB / 1.952GiB',
                                                                         'MemPerc' => '4.76%',
                                                                         'NetIO' => '856B / 1.45kB',
                                                                         'BlockIO' => '2.34MB / 890kB'
                                                                       }
                                                                     })
      end

      it 'collects CPU usage metrics for all services' do
        metrics = collector.collect_service_metrics

        aggregate_failures do
          expect(metrics[:gateway][:cpu_percent]).to eq(2.45)
          expect(metrics[:personas][:cpu_percent]).to eq(1.20)
        end
      end

      it 'collects memory usage metrics for all services' do
        metrics = collector.collect_service_metrics

        aggregate_failures do
          expect(metrics[:gateway][:memory_usage_mb]).to be_within(0.1).of(128.5)
          expect(metrics[:gateway][:memory_percent]).to eq(6.43)
          expect(metrics[:personas][:memory_usage_mb]).to be_within(0.1).of(95.2)
          expect(metrics[:personas][:memory_percent]).to eq(4.76)
        end
      end

      it 'collects network I/O metrics' do
        metrics = collector.collect_service_metrics

        aggregate_failures do
          expect(metrics[:gateway][:network_rx_bytes]).to be_a(Numeric)
          expect(metrics[:gateway][:network_tx_bytes]).to be_a(Numeric)
          expect(metrics[:personas][:network_rx_bytes]).to be_a(Numeric)
          expect(metrics[:personas][:network_tx_bytes]).to be_a(Numeric)
        end
      end

      it 'includes timestamp for all metrics' do
        metrics = collector.collect_service_metrics

        expect(metrics[:gateway][:timestamp]).to be_a(Time)
        expect(metrics[:personas][:timestamp]).to be_a(Time)
      end
    end

    context 'when Docker stats are unavailable' do
      before do
        allow(collector).to receive(:docker_stats_output).and_return({})
      end

      it 'returns empty metrics' do
        metrics = collector.collect_service_metrics

        expect(metrics).to be_empty
      end
    end
  end

  describe '#collect_response_time_metrics' do
    let(:health_endpoints) do
      {
        gateway: 'http://localhost:3000/health',
        personas: 'http://localhost:3001/health',
        workflows: 'http://localhost:3002/health'
      }
    end

    before do
      allow(collector).to receive(:measure_response_time)
        .with('http://localhost:3000/health')
        .and_return(0.145)

      allow(collector).to receive(:measure_response_time)
        .with('http://localhost:3001/health')
        .and_return(0.098)

      allow(collector).to receive(:measure_response_time)
        .with('http://localhost:3002/health')
        .and_return(nil) # Service down
    end

    it 'measures response times for available services' do
      metrics = collector.collect_response_time_metrics(health_endpoints)

      aggregate_failures do
        expect(metrics[:gateway][:response_time_ms]).to eq(145.0)
        expect(metrics[:personas][:response_time_ms]).to eq(98.0)
        expect(metrics[:gateway][:status]).to eq('responding')
        expect(metrics[:personas][:status]).to eq('responding')
      end
    end

    it 'handles non-responding services' do
      metrics = collector.collect_response_time_metrics(health_endpoints)

      aggregate_failures do
        expect(metrics[:workflows][:response_time_ms]).to be_nil
        expect(metrics[:workflows][:status]).to eq('not_responding')
      end
    end

    it 'includes timestamps for all response time measurements' do
      metrics = collector.collect_response_time_metrics(health_endpoints)

      expect(metrics[:gateway][:timestamp]).to be_a(Time)
      expect(metrics[:personas][:timestamp]).to be_a(Time)
      expect(metrics[:workflows][:timestamp]).to be_a(Time)
    end
  end

  describe '#aggregate_metrics' do
    let(:service_metrics) do
      {
        gateway: { cpu_percent: 2.45, memory_percent: 6.43, timestamp: Time.now },
        personas: { cpu_percent: 1.20, memory_percent: 4.76, timestamp: Time.now }
      }
    end

    let(:response_metrics) do
      {
        gateway: { response_time_ms: 145.0, status: 'responding', timestamp: Time.now },
        personas: { response_time_ms: 98.0, status: 'responding', timestamp: Time.now }
      }
    end

    it 'combines service and response time metrics' do
      combined = collector.aggregate_metrics(service_metrics, response_metrics)

      aggregate_failures do
        expect(combined[:gateway]).to include(
          cpu_percent: 2.45,
          memory_percent: 6.43,
          response_time_ms: 145.0,
          status: 'responding'
        )
        expect(combined[:personas]).to include(
          cpu_percent: 1.20,
          memory_percent: 4.76,
          response_time_ms: 98.0,
          status: 'responding'
        )
      end
    end

    it 'calculates system-wide averages' do
      combined = collector.aggregate_metrics(service_metrics, response_metrics)

      aggregate_failures do
        expect(combined[:system_averages][:avg_cpu_percent]).to be_within(0.01).of(1.83)
        expect(combined[:system_averages][:avg_memory_percent]).to be_within(0.01).of(5.60)
        expect(combined[:system_averages][:avg_response_time_ms]).to be_within(0.1).of(121.5)
      end
    end
  end

  describe '#metrics_history' do
    it 'maintains a rolling history of metrics collections' do
      # Simulate multiple metric collections
      3.times do |i|
        allow(collector).to receive(:collect_service_metrics).and_return({
                                                                           gateway: { cpu_percent: i * 1.0,
                                                                                      timestamp: Time.now }
                                                                         })
        collector.collect_and_store_metrics
      end

      history = collector.metrics_history

      aggregate_failures do
        expect(history.size).to eq(3)
        expect(history.last[:gateway][:cpu_percent]).to eq(2.0)
      end
    end

    it 'limits history to configurable size' do
      collector = described_class.new(max_history: 5)

      7.times do |i|
        allow(collector).to receive(:collect_service_metrics).and_return({
                                                                           gateway: { cpu_percent: i * 1.0,
                                                                                      timestamp: Time.now }
                                                                         })
        collector.collect_and_store_metrics
      end

      expect(collector.metrics_history.size).to eq(5)
    end
  end
end
