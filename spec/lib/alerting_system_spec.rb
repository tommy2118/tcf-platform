# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/alerting_system'

RSpec.describe TcfPlatform::AlertingSystem do
  let(:alerting_system) { described_class.new }

  describe '#configure_thresholds' do
    it 'allows setting CPU threshold limits' do
      alerting_system.configure_thresholds(cpu_percent: { warning: 70.0, critical: 90.0 })

      thresholds = alerting_system.thresholds

      aggregate_failures do
        expect(thresholds[:cpu_percent][:warning]).to eq(70.0)
        expect(thresholds[:cpu_percent][:critical]).to eq(90.0)
      end
    end

    it 'allows setting memory threshold limits' do
      alerting_system.configure_thresholds(memory_percent: { warning: 80.0, critical: 95.0 })

      thresholds = alerting_system.thresholds

      aggregate_failures do
        expect(thresholds[:memory_percent][:warning]).to eq(80.0)
        expect(thresholds[:memory_percent][:critical]).to eq(95.0)
      end
    end

    it 'allows setting response time threshold limits' do
      alerting_system.configure_thresholds(response_time_ms: { warning: 1000, critical: 5000 })

      thresholds = alerting_system.thresholds

      aggregate_failures do
        expect(thresholds[:response_time_ms][:warning]).to eq(1000)
        expect(thresholds[:response_time_ms][:critical]).to eq(5000)
      end
    end

    it 'allows setting multiple thresholds at once' do
      alerting_system.configure_thresholds(
        cpu_percent: { warning: 60.0, critical: 85.0 },
        memory_percent: { warning: 75.0, critical: 90.0 },
        response_time_ms: { warning: 800, critical: 3000 }
      )

      thresholds = alerting_system.thresholds

      aggregate_failures do
        expect(thresholds[:cpu_percent][:warning]).to eq(60.0)
        expect(thresholds[:memory_percent][:critical]).to eq(90.0)
        expect(thresholds[:response_time_ms][:warning]).to eq(800)
      end
    end
  end

  describe '#check_thresholds' do
    before do
      alerting_system.configure_thresholds(
        cpu_percent: { warning: 70.0, critical: 90.0 },
        memory_percent: { warning: 80.0, critical: 95.0 },
        response_time_ms: { warning: 1000, critical: 5000 }
      )
    end

    context 'when all metrics are within normal ranges' do
      let(:metrics) do
        {
          gateway: {
            cpu_percent: 45.2,
            memory_percent: 62.1,
            response_time_ms: 250.0,
            timestamp: Time.now
          },
          personas: {
            cpu_percent: 38.7,
            memory_percent: 58.9,
            response_time_ms: 180.0,
            timestamp: Time.now
          }
        }
      end

      it 'returns no alerts' do
        alerts = alerting_system.check_thresholds(metrics)
        expect(alerts).to be_empty
      end

      it 'records metrics as healthy' do
        alerting_system.check_thresholds(metrics)
        history = alerting_system.alert_history

        expect(history.last[:status]).to eq('healthy')
      end
    end

    context 'when some metrics exceed warning thresholds' do
      let(:metrics) do
        {
          gateway: {
            cpu_percent: 75.5, # Warning level
            memory_percent: 62.1,
            response_time_ms: 1250.0, # Warning level
            timestamp: Time.now
          },
          personas: {
            cpu_percent: 38.7,
            memory_percent: 85.2, # Warning level
            response_time_ms: 180.0,
            timestamp: Time.now
          }
        }
      end

      it 'generates warning level alerts' do
        alerts = alerting_system.check_thresholds(metrics)

        aggregate_failures do
          expect(alerts.size).to eq(3)
          expect(alerts).to all(include(level: 'warning'))

          alert_messages = alerts.map { |a| a[:message] }
          expect(alert_messages).to include(match(/gateway.*CPU usage.*75.5%.*exceeds warning threshold/))
          expect(alert_messages).to include(match(/gateway.*response time.*1250.0ms.*exceeds warning threshold/))
          expect(alert_messages).to include(match(/personas.*memory usage.*85.2%.*exceeds warning threshold/))
        end
      end

      it 'includes service name and metric details in alerts' do
        alerts = alerting_system.check_thresholds(metrics)
        cpu_alert = alerts.find { |a| a[:message].include?('CPU usage') }

        aggregate_failures do
          expect(cpu_alert[:service]).to eq('gateway')
          expect(cpu_alert[:metric]).to eq('cpu_percent')
          expect(cpu_alert[:current_value]).to eq(75.5)
          expect(cpu_alert[:threshold_value]).to eq(70.0)
          expect(cpu_alert[:timestamp]).to be_a(Time)
        end
      end
    end

    context 'when some metrics exceed critical thresholds' do
      let(:metrics) do
        {
          gateway: {
            cpu_percent: 92.3, # Critical level
            memory_percent: 62.1,
            response_time_ms: 250.0,
            timestamp: Time.now
          },
          personas: {
            cpu_percent: 38.7,
            memory_percent: 97.8, # Critical level
            response_time_ms: 6500.0, # Critical level
            timestamp: Time.now
          }
        }
      end

      it 'generates critical level alerts' do
        alerts = alerting_system.check_thresholds(metrics)

        aggregate_failures do
          expect(alerts.size).to eq(3)
          expect(alerts.count { |a| a[:level] == 'critical' }).to eq(3)

          alert_messages = alerts.map { |a| a[:message] }
          expect(alert_messages).to include(match(/gateway.*CPU usage.*92.3%.*exceeds critical threshold/))
          expect(alert_messages).to include(match(/personas.*memory usage.*97.8%.*exceeds critical threshold/))
          expect(alert_messages).to include(match(/personas.*response time.*6500.0ms.*exceeds critical threshold/))
        end
      end
    end

    context 'when metrics have mixed threshold violations' do
      let(:metrics) do
        {
          gateway: {
            cpu_percent: 75.5, # Warning
            memory_percent: 97.2, # Critical
            response_time_ms: 250.0, # Normal
            timestamp: Time.now
          }
        }
      end

      it 'generates alerts at appropriate levels' do
        alerts = alerting_system.check_thresholds(metrics)

        aggregate_failures do
          expect(alerts.size).to eq(2)

          cpu_alert = alerts.find { |a| a[:metric] == 'cpu_percent' }
          memory_alert = alerts.find { |a| a[:metric] == 'memory_percent' }

          expect(cpu_alert[:level]).to eq('warning')
          expect(memory_alert[:level]).to eq('critical')
        end
      end
    end
  end

  describe '#alert_history' do
    before do
      alerting_system.configure_thresholds(cpu_percent: { warning: 70.0, critical: 90.0 })
    end

    it 'maintains a history of threshold checks' do
      # First check - healthy
      healthy_metrics = { gateway: { cpu_percent: 45.0, timestamp: Time.now } }
      alerting_system.check_thresholds(healthy_metrics)

      # Second check - warning
      warning_metrics = { gateway: { cpu_percent: 75.0, timestamp: Time.now } }
      alerting_system.check_thresholds(warning_metrics)

      history = alerting_system.alert_history

      aggregate_failures do
        expect(history.size).to eq(2)
        expect(history.first[:status]).to eq('healthy')
        expect(history.last[:status]).to eq('warning')
        expect(history.last[:alerts_count]).to eq(1)
      end
    end

    it 'limits history to configurable maximum size' do
      alerting_system = described_class.new(max_history: 3)
      alerting_system.configure_thresholds(cpu_percent: { warning: 70.0, critical: 90.0 })

      # Generate 5 threshold checks
      5.times do |i|
        metrics = { gateway: { cpu_percent: 50.0 + i, timestamp: Time.now } }
        alerting_system.check_thresholds(metrics)
      end

      expect(alerting_system.alert_history.size).to eq(3)
    end

    it 'includes timestamps and alert counts in history' do
      metrics = { gateway: { cpu_percent: 75.0, timestamp: Time.now } }
      alerting_system.check_thresholds(metrics)

      history_entry = alerting_system.alert_history.last

      aggregate_failures do
        expect(history_entry[:timestamp]).to be_a(Time)
        expect(history_entry[:alerts_count]).to eq(1)
        expect(history_entry[:status]).to eq('warning')
      end
    end
  end

  describe '#active_alerts' do
    before do
      alerting_system.configure_thresholds(
        cpu_percent: { warning: 70.0, critical: 90.0 },
        memory_percent: { warning: 80.0, critical: 95.0 }
      )
    end

    context 'when there are ongoing threshold violations' do
      it 'returns currently active alerts' do
        metrics = {
          gateway: { cpu_percent: 92.0, memory_percent: 85.0, timestamp: Time.now },
          personas: { cpu_percent: 45.0, memory_percent: 60.0, timestamp: Time.now }
        }

        alerting_system.check_thresholds(metrics)
        active_alerts = alerting_system.active_alerts

        aggregate_failures do
          expect(active_alerts.size).to eq(2)
          expect(active_alerts.map { |a| a[:level] }).to contain_exactly('critical', 'warning')
          expect(active_alerts.map { |a| a[:service] }).to all(eq('gateway'))
        end
      end
    end

    context 'when metrics return to normal' do
      it 'clears active alerts for resolved issues' do
        # First check - violations
        high_metrics = { gateway: { cpu_percent: 92.0, timestamp: Time.now } }
        alerting_system.check_thresholds(high_metrics)

        expect(alerting_system.active_alerts).not_to be_empty

        # Second check - normal
        normal_metrics = { gateway: { cpu_percent: 45.0, timestamp: Time.now } }
        alerting_system.check_thresholds(normal_metrics)

        expect(alerting_system.active_alerts).to be_empty
      end
    end
  end

  describe '#thresholds' do
    it 'returns default thresholds when none configured' do
      thresholds = alerting_system.thresholds

      aggregate_failures do
        expect(thresholds[:cpu_percent][:warning]).to eq(80.0)
        expect(thresholds[:cpu_percent][:critical]).to eq(95.0)
        expect(thresholds[:memory_percent][:warning]).to eq(85.0)
        expect(thresholds[:memory_percent][:critical]).to eq(98.0)
        expect(thresholds[:response_time_ms][:warning]).to eq(2000)
        expect(thresholds[:response_time_ms][:critical]).to eq(10_000)
      end
    end

    it 'returns configured custom thresholds' do
      alerting_system.configure_thresholds(cpu_percent: { warning: 60.0, critical: 85.0 })

      thresholds = alerting_system.thresholds

      aggregate_failures do
        expect(thresholds[:cpu_percent][:warning]).to eq(60.0)
        expect(thresholds[:cpu_percent][:critical]).to eq(85.0)
        # Other thresholds should remain at defaults
        expect(thresholds[:memory_percent][:warning]).to eq(85.0)
      end
    end
  end
end
