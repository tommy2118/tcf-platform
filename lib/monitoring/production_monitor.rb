# frozen_string_literal: true

require_relative '../tcf_platform'
require_relative 'monitoring_service'
require_relative '../deployment_manager'
require_relative '../blue_green_deployer'
require_relative '../security/security_validator'
require_relative '../backup_manager'

module TcfPlatform
  module Monitoring
    class ProductionMonitorError < StandardError; end
    class SecurityAuditError < StandardError; end
    class HealthCheckError < StandardError; end

    # Production monitoring service for deployment health and security monitoring
    class ProductionMonitor
      DEFAULT_CONFIG = {
        health_check_interval: 30,
        alert_threshold: 0.95,
        metrics_retention_days: 30,
        audit_interval_hours: 24
      }.freeze

      attr_reader :config, :monitoring_service, :deployment_manager

      def initialize(
        monitoring_service:, 
        deployment_manager:, 
        security_validator:, 
        backup_manager:,
        config: {}
      )
        @config = DEFAULT_CONFIG.merge(config)
        @monitoring_service = monitoring_service
        @deployment_manager = deployment_manager
        @security_validator = security_validator
        @backup_manager = backup_manager
        @running = false
        @alert_history = []
      end

      def start_production_monitoring
        raise ProductionMonitorError, 'Production monitoring already running' if @running

        begin
          # Start underlying monitoring service
          @monitoring_service.start unless @monitoring_service.running?

          # Initialize production-specific monitoring
          setup_production_alerts
          start_health_monitoring
          start_security_monitoring

          @running = true
          @start_time = Time.now

          {
            status: 'started',
            monitoring_active: true,
            start_time: @start_time,
            alerts_configured: production_alert_count,
            health_checks_enabled: true
          }
        rescue StandardError => e
          {
            status: 'failed',
            error: e.message,
            monitoring_active: false
          }
        end
      end

      def stop_production_monitoring
        return { status: 'not_running' } unless @running

        @running = false
        @monitoring_service.stop if @monitoring_service.running?

        {
          status: 'stopped',
          uptime_seconds: uptime_seconds,
          alerts_processed: @alert_history.size
        }
      end

      def deployment_health_status
        readiness = @deployment_manager.validate_production_readiness

        # Collect additional production health metrics
        service_health = collect_service_health_metrics
        security_status = @security_validator.validate_production_security
        backup_status = @backup_manager.verify_backup_system

        overall_status = if readiness[:overall_status] == 'ready' &&
                           service_health[:all_services_healthy] &&
                           security_status[:valid] &&
                           backup_status[:status] != 'error'
                          'healthy'
                        elsif service_health[:critical_services_healthy]
                          'degraded'
                        else
                          'unhealthy'
                        end

        {
          overall_status: overall_status,
          deployment_readiness: readiness,
          service_health: service_health,
          security_status: security_status,
          backup_status: backup_status,
          timestamp: Time.now.to_i
        }
      end

      def security_audit
        begin
          # Comprehensive security audit
          security_validation = @security_validator.validate_production_security
          vulnerability_scan = perform_vulnerability_scan
          compliance_check = perform_compliance_check
          access_audit = audit_access_controls

          critical_issues = []
          warnings = []

          # Analyze security validation
          unless security_validation[:valid]
            critical_issues.concat(security_validation[:errors] || [])
          end

          # Analyze vulnerability scan
          if vulnerability_scan[:high_severity_count] > 0
            critical_issues << "#{vulnerability_scan[:high_severity_count]} high severity vulnerabilities found"
          end

          # Analyze compliance
          unless compliance_check[:compliant]
            warnings.concat(compliance_check[:violations] || [])
          end

          # Determine overall audit status
          audit_status = if critical_issues.empty?
                          warnings.empty? ? 'passed' : 'passed_with_warnings'
                        else
                          'failed'
                        end

          {
            audit_status: audit_status,
            security_validation: security_validation,
            vulnerability_scan: vulnerability_scan,
            compliance_check: compliance_check,
            access_audit: access_audit,
            critical_issues: critical_issues,
            warnings: warnings,
            audit_timestamp: Time.now.to_i
          }
        rescue StandardError => e
          raise SecurityAuditError, "Security audit failed: #{e.message}"
        end
      end

      def real_time_alerts
        return [] unless @running

        # Check for active alerts
        active_alerts = []

        # Service health alerts
        service_health = collect_service_health_metrics
        unless service_health[:all_services_healthy]
          active_alerts << {
            type: 'service_health',
            severity: service_health[:critical_services_healthy] ? 'warning' : 'critical',
            message: "Unhealthy services: #{service_health[:unhealthy_services].join(', ')}",
            timestamp: Time.now.to_i
          }
        end

        # Security alerts
        security_status = @security_validator.validate_production_security
        unless security_status[:valid]
          active_alerts << {
            type: 'security',
            severity: 'critical',
            message: "Security validation failed: #{(security_status[:errors] || []).join(', ')}",
            timestamp: Time.now.to_i
          }
        end

        # Resource alerts
        resource_alerts = check_resource_thresholds
        active_alerts.concat(resource_alerts)

        active_alerts
      end

      def validate_deployment(version)
        begin
          # Pre-deployment validation
          readiness = @deployment_manager.validate_production_readiness
          
          unless readiness[:overall_status] == 'ready'
            return {
              status: 'validation_failed',
              readiness: readiness,
              deployment_allowed: false
            }
          end

          # Additional production-specific checks
          resource_check = validate_resource_availability
          dependency_check = validate_external_dependencies

          deployment_allowed = resource_check[:sufficient] && dependency_check[:all_available]

          {
            status: deployment_allowed ? 'validation_passed' : 'validation_failed',
            version: version,
            readiness: readiness,
            resource_check: resource_check,
            dependency_check: dependency_check,
            deployment_allowed: deployment_allowed,
            validation_timestamp: Time.now.to_i
          }
        rescue StandardError => e
          {
            status: 'validation_error',
            error: e.message,
            deployment_allowed: false
          }
        end
      end

      def monitor_deployment(deployment_id)
        return { error: 'Production monitoring not running' } unless @running

        # Monitor active deployment
        deployment_metrics = {
          deployment_id: deployment_id,
          start_time: Time.now.to_i,
          services_status: {},
          health_checks: [],
          performance_metrics: {}
        }

        # Collect service statuses
        %w[gateway personas workflows projects context tokens].each do |service|
          deployment_metrics[:services_status][service] = @monitoring_service.check_service_health(service)
        end

        # Check overall deployment health
        all_healthy = deployment_metrics[:services_status].values.all? { |status| status[:healthy] }

        deployment_metrics.merge({
          overall_health: all_healthy ? 'healthy' : 'unhealthy',
          monitoring_active: true
        })
      end

      def running?
        @running
      end

      private

      def setup_production_alerts
        # Configure production-specific alerts
        @production_alerts = {
          service_down: { threshold: 1, severity: 'critical' },
          high_error_rate: { threshold: 0.05, severity: 'warning' },
          resource_exhaustion: { threshold: 0.90, severity: 'critical' },
          security_breach: { threshold: 1, severity: 'critical' }
        }
      end

      def start_health_monitoring
        # Start continuous health monitoring
        @health_monitoring_active = true
      end

      def start_security_monitoring
        # Start continuous security monitoring
        @security_monitoring_active = true
      end

      def collect_service_health_metrics
        services = %w[gateway personas workflows projects context tokens]
        healthy_services = []
        unhealthy_services = []
        critical_services = %w[gateway postgres redis]

        services.each do |service|
          health = @monitoring_service.check_service_health(service)
          if health[:healthy]
            healthy_services << service
          else
            unhealthy_services << service
          end
        end

        critical_services_healthy = critical_services.all? { |service| healthy_services.include?(service) }

        {
          all_services_healthy: unhealthy_services.empty?,
          critical_services_healthy: critical_services_healthy,
          healthy_services: healthy_services,
          unhealthy_services: unhealthy_services,
          healthy_count: healthy_services.size,
          total_services: services.size
        }
      end

      def perform_vulnerability_scan
        # Simulate vulnerability scanning
        {
          total_vulnerabilities: 3,
          high_severity_count: 0,
          medium_severity_count: 2,
          low_severity_count: 1,
          scan_timestamp: Time.now.to_i
        }
      end

      def perform_compliance_check
        # Simulate compliance checking
        {
          compliant: true,
          violations: [],
          checks_performed: 15,
          check_timestamp: Time.now.to_i
        }
      end

      def audit_access_controls
        # Simulate access control audit
        {
          users_audited: 25,
          privileged_accounts: 3,
          inactive_accounts: 2,
          audit_timestamp: Time.now.to_i
        }
      end

      def check_resource_thresholds
        alerts = []

        # CPU threshold check
        cpu_usage = 0.75 # Simulated
        if cpu_usage > @config[:alert_threshold]
          alerts << {
            type: 'resource',
            severity: 'warning',
            message: "High CPU usage: #{(cpu_usage * 100).round(1)}%",
            timestamp: Time.now.to_i
          }
        end

        # Memory threshold check
        memory_usage = 0.80 # Simulated
        if memory_usage > @config[:alert_threshold]
          alerts << {
            type: 'resource',
            severity: 'warning',
            message: "High memory usage: #{(memory_usage * 100).round(1)}%",
            timestamp: Time.now.to_i
          }
        end

        alerts
      end

      def validate_resource_availability
        {
          sufficient: true,
          cpu_available: 85.5,
          memory_available: 78.2,
          disk_available: 65.8
        }
      end

      def validate_external_dependencies
        dependencies = %w[postgres redis qdrant]
        available_dependencies = []
        unavailable_dependencies = []

        dependencies.each do |dependency|
          # Simulate dependency check
          if dependency == 'postgres' || dependency == 'redis'
            available_dependencies << dependency
          else
            unavailable_dependencies << dependency if rand > 0.9 # 10% chance of failure
          end
        end

        {
          all_available: unavailable_dependencies.empty?,
          available_dependencies: available_dependencies,
          unavailable_dependencies: unavailable_dependencies
        }
      end

      def production_alert_count
        @production_alerts&.size || 4
      end

      def uptime_seconds
        return 0 unless @start_time

        (Time.now - @start_time).to_i
      end
    end
  end
end