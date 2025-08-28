# frozen_string_literal: true

require_relative 'docker_manager'

module TcfPlatform
  # Service Health Monitoring System
  # Provides comprehensive health aggregation and monitoring for all TCF Platform services
  class ServiceHealthMonitor
    attr_reader :health_check_history

    MAX_HISTORY_SIZE = 100

    def initialize
      @docker_manager = DockerManager.new
      @health_check_history = []
    end

    # rubocop:disable Metrics/MethodLength
    def aggregate_health_status
      service_statuses = @docker_manager.service_status

      healthy_services = service_statuses.select { |_, status| healthy?(status) }
      unhealthy_services = service_statuses.reject { |_, status| healthy?(status) }

      overall_status = determine_overall_status(healthy_services.size, unhealthy_services.size)

      result = {
        overall_status: overall_status,
        healthy_count: healthy_services.size,
        unhealthy_count: unhealthy_services.size,
        total_services: service_statuses.size,
        services: service_statuses,
        unhealthy_services: unhealthy_services.keys,
        timestamp: Time.now
      }

      record_health_check(result)
      result
    end
    # rubocop:enable Metrics/MethodLength

    def service_uptime(service_name)
      @docker_manager.service_uptime(service_name)
    end

    private

    def healthy?(service_status)
      service_status[:status] == 'running' && service_status[:health] == 'healthy'
    end

    def determine_overall_status(healthy_count, unhealthy_count)
      total_services = healthy_count + unhealthy_count

      return 'healthy' if unhealthy_count.zero? && total_services.positive?
      return 'critical' if healthy_count.zero? && total_services.positive?
      return 'degraded' if unhealthy_count.positive?

      'unknown'
    end

    def record_health_check(health_data)
      @health_check_history << health_data

      # Maintain history limit
      @health_check_history.shift if @health_check_history.size > MAX_HISTORY_SIZE
    end
  end
end
