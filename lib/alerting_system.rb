# frozen_string_literal: true

module TcfPlatform
  # Configurable alerting system for monitoring service metrics and thresholds
  class AlertingSystem
    DEFAULT_THRESHOLDS = {
      cpu_percent: { warning: 80.0, critical: 95.0 },
      memory_percent: { warning: 85.0, critical: 98.0 },
      response_time_ms: { warning: 2000, critical: 10_000 }
    }.freeze

    def initialize(max_history: 100)
      @max_history = max_history
      @thresholds = DEFAULT_THRESHOLDS.dup
      @alert_history = []
      @active_alerts = []
    end

    def configure_thresholds(threshold_config)
      @thresholds.merge!(threshold_config)
    end

    attr_reader :thresholds, :active_alerts, :alert_history

    def check_thresholds(metrics)
      alerts = []

      metrics.each do |service_name, service_metrics|
        alerts.concat(check_service_thresholds(service_name.to_s, service_metrics))
      end

      update_active_alerts(alerts)
      record_threshold_check(alerts)

      alerts
    end

    private

    def check_service_thresholds(service_name, service_metrics)
      alerts = []

      @thresholds.each do |metric_name, threshold_config|
        next unless service_metrics.key?(metric_name)

        current_value = service_metrics[metric_name]
        next unless current_value.is_a?(Numeric)

        alert = check_metric_threshold(service_name, metric_name, current_value, threshold_config)
        alerts << alert if alert
      end

      alerts
    end

    def check_metric_threshold(service_name, metric_name, current_value, threshold_config)
      if current_value >= threshold_config[:critical]
        create_alert(service_name, metric_name, current_value, 'critical', threshold_config[:critical])
      elsif current_value >= threshold_config[:warning]
        create_alert(service_name, metric_name, current_value, 'warning', threshold_config[:warning])
      end
    end

    def create_alert(service_name, metric_name, current_value, level, threshold_value)
      {
        service: service_name,
        metric: metric_name.to_s,
        current_value: current_value,
        threshold_value: threshold_value,
        level: level,
        message: build_alert_message(service_name, metric_name, current_value, level, threshold_value),
        timestamp: Time.now
      }
    end

    def build_alert_message(service_name, metric_name, current_value, level, threshold_value)
      metric_display = format_metric_display(metric_name, current_value)
      "#{service_name} #{metric_display} exceeds #{level} threshold of #{format_threshold_value(metric_name,
                                                                                                threshold_value)}"
    end

    def format_metric_display(metric_name, current_value)
      case metric_name.to_s
      when 'cpu_percent'
        "CPU usage at #{current_value}%"
      when 'memory_percent'
        "memory usage at #{current_value}%"
      when 'response_time_ms'
        "response time at #{current_value}ms"
      else
        "#{metric_name} at #{current_value}"
      end
    end

    def format_threshold_value(metric_name, threshold_value)
      case metric_name.to_s
      when 'cpu_percent', 'memory_percent'
        "#{threshold_value}%"
      when 'response_time_ms'
        "#{threshold_value}ms"
      else
        threshold_value.to_s
      end
    end

    def update_active_alerts(new_alerts)
      @active_alerts = new_alerts.dup
    end

    def record_threshold_check(alerts)
      status = determine_overall_alert_status(alerts)

      @alert_history << {
        timestamp: Time.now,
        status: status,
        alerts_count: alerts.size
      }

      # Maintain history limit
      @alert_history.shift if @alert_history.size > @max_history
    end

    def determine_overall_alert_status(alerts)
      return 'healthy' if alerts.empty?
      return 'critical' if alerts.any? { |alert| alert[:level] == 'critical' }

      'warning'
    end
  end
end
