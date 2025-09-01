# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/monitoring/production_monitor'
require_relative '../../../lib/monitoring/monitoring_service'
require_relative '../../../lib/deployment_manager'
require_relative '../../../lib/security/security_validator'
require_relative '../../../lib/backup_manager'

RSpec.describe TcfPlatform::Monitoring::ProductionMonitor do
  let(:monitoring_service) { instance_double(TcfPlatform::Monitoring::MonitoringService) }
  let(:deployment_manager) { instance_double(TcfPlatform::DeploymentManager) }
  let(:security_validator) { instance_double(TcfPlatform::SecurityValidator) }
  let(:backup_manager) { instance_double(TcfPlatform::BackupManager) }
  let(:config) { { health_check_interval: 15, alert_threshold: 0.90 } }

  subject do
    described_class.new(
      monitoring_service: monitoring_service,
      deployment_manager: deployment_manager,
      security_validator: security_validator,
      backup_manager: backup_manager,
      config: config
    )
  end

  describe '#initialize' do
    it 'sets up production monitoring with required dependencies' do
      expect(subject.monitoring_service).to eq(monitoring_service)
      expect(subject.deployment_manager).to eq(deployment_manager)
      expect(subject.config[:health_check_interval]).to eq(15)
      expect(subject.config[:alert_threshold]).to eq(0.90)
    end

    it 'merges custom config with defaults' do
      expect(subject.config[:metrics_retention_days]).to eq(30)
      expect(subject.config[:audit_interval_hours]).to eq(24)
    end

    it 'initializes in stopped state' do
      expect(subject.running?).to be false
    end
  end

  describe '#start_production_monitoring' do
    context 'when monitoring is not running' do
      before do
        allow(monitoring_service).to receive(:running?).and_return(false)
        allow(monitoring_service).to receive(:start)
      end

      it 'starts production monitoring successfully' do
        result = subject.start_production_monitoring

        expect(result[:status]).to eq('started')
        expect(result[:monitoring_active]).to be true
        expect(result[:start_time]).to be_a(Time)
        expect(result[:alerts_configured]).to be > 0
        expect(result[:health_checks_enabled]).to be true
      end

      it 'starts underlying monitoring service' do
        expect(monitoring_service).to receive(:start)
        subject.start_production_monitoring
      end

      it 'sets running state to true' do
        subject.start_production_monitoring
        expect(subject.running?).to be true
      end
    end

    context 'when monitoring is already running' do
      before do
        allow(subject).to receive(:running?).and_return(true)
      end

      it 'raises error for already running monitoring' do
        expect { subject.start_production_monitoring }
          .to raise_error(TcfPlatform::Monitoring::ProductionMonitorError, 
                         'Production monitoring already running')
      end
    end

    context 'when setup fails' do
      before do
        allow(monitoring_service).to receive(:running?).and_return(false)
        allow(monitoring_service).to receive(:start).and_raise(StandardError, 'Setup failed')
      end

      it 'returns failure status with error' do
        result = subject.start_production_monitoring

        expect(result[:status]).to eq('failed')
        expect(result[:error]).to eq('Setup failed')
        expect(result[:monitoring_active]).to be false
      end
    end
  end

  describe '#stop_production_monitoring' do
    context 'when monitoring is running' do
      before do
        allow(subject).to receive(:running?).and_return(true)
        allow(monitoring_service).to receive(:running?).and_return(true)
        allow(monitoring_service).to receive(:stop)
        
        # Simulate some uptime
        subject.instance_variable_set(:@start_time, Time.now - 3600)
        subject.instance_variable_set(:@alert_history, [1, 2, 3])
      end

      it 'stops production monitoring successfully' do
        result = subject.stop_production_monitoring

        expect(result[:status]).to eq('stopped')
        expect(result[:uptime_seconds]).to be > 3500
        expect(result[:alerts_processed]).to eq(3)
      end

      it 'stops underlying monitoring service' do
        expect(monitoring_service).to receive(:stop)
        subject.stop_production_monitoring
      end
    end

    context 'when monitoring is not running' do
      before do
        allow(subject).to receive(:running?).and_return(false)
      end

      it 'returns not running status' do
        result = subject.stop_production_monitoring
        expect(result[:status]).to eq('not_running')
      end
    end
  end

  describe '#deployment_health_status' do
    let(:readiness_result) do
      {
        overall_status: 'ready',
        security: { valid: true },
        infrastructure: { all_ready: true },
        services: { all_healthy: true, tests_passing: true }
      }
    end

    let(:security_status) { { valid: true } }
    let(:backup_status) { { status: 'healthy' } }

    before do
      allow(deployment_manager).to receive(:validate_production_readiness)
        .and_return(readiness_result)
      allow(security_validator).to receive(:validate_production_security)
        .and_return(security_status)
      allow(backup_manager).to receive(:verify_backup_system)
        .and_return(backup_status)
    end

    context 'when all systems are healthy' do
      it 'returns healthy overall status' do
        result = subject.deployment_health_status

        expect(result[:overall_status]).to eq('healthy')
        expect(result[:deployment_readiness]).to eq(readiness_result)
        expect(result[:security_status]).to eq(security_status)
        expect(result[:backup_status]).to eq(backup_status)
        expect(result[:timestamp]).to be_a(Integer)
      end

      it 'includes service health metrics' do
        result = subject.deployment_health_status

        service_health = result[:service_health]
        expect(service_health[:all_services_healthy]).to be true
        expect(service_health[:critical_services_healthy]).to be true
        expect(service_health[:healthy_count]).to be > 0
        expect(service_health[:total_services]).to be > 0
      end
    end

    context 'when deployment is not ready' do
      let(:readiness_result) do
        {
          overall_status: 'not_ready',
          security: { valid: false, errors: ['SSL certificate expired'] }
        }
      end

      it 'returns unhealthy status' do
        result = subject.deployment_health_status
        expect(result[:overall_status]).to eq('unhealthy')
      end
    end

    context 'when critical services are healthy but others are not' do
      before do
        # Mock service health to show some services unhealthy
        allow(monitoring_service).to receive(:check_service_health) do |service|
          if %w[gateway postgres redis].include?(service)
            { healthy: true }
          else
            { healthy: false }
          end
        end
      end

      it 'returns degraded status' do
        result = subject.deployment_health_status
        expect(result[:overall_status]).to eq('degraded')
      end
    end
  end

  describe '#security_audit' do
    let(:security_validation) { { valid: true } }
    let(:vulnerability_scan) do
      {
        total_vulnerabilities: 5,
        high_severity_count: 1,
        medium_severity_count: 2,
        low_severity_count: 2
      }
    end

    before do
      allow(security_validator).to receive(:validate_production_security)
        .and_return(security_validation)
    end

    context 'when audit passes with no critical issues' do
      let(:vulnerability_scan) do
        {
          total_vulnerabilities: 2,
          high_severity_count: 0,
          medium_severity_count: 1,
          low_severity_count: 1
        }
      end

      it 'returns passed audit status' do
        result = subject.security_audit

        expect(result[:audit_status]).to eq('passed')
        expect(result[:critical_issues]).to be_empty
        expect(result[:security_validation]).to eq(security_validation)
        expect(result[:vulnerability_scan][:high_severity_count]).to eq(0)
        expect(result[:audit_timestamp]).to be_a(Integer)
      end
    end

    context 'when audit has critical issues' do
      let(:security_validation) do
        { 
          valid: false, 
          errors: ['SSL certificate expired', 'Weak encryption detected'] 
        }
      end

      it 'returns failed audit status with critical issues' do
        result = subject.security_audit

        expect(result[:audit_status]).to eq('failed')
        expect(result[:critical_issues]).to include(
          'SSL certificate expired',
          'Weak encryption detected'
        )
      end
    end

    context 'when audit has high severity vulnerabilities' do
      let(:vulnerability_scan) do
        {
          total_vulnerabilities: 5,
          high_severity_count: 2,
          medium_severity_count: 2,
          low_severity_count: 1
        }
      end

      it 'includes vulnerability issues in critical issues' do
        result = subject.security_audit

        expect(result[:audit_status]).to eq('failed')
        expect(result[:critical_issues]).to include('2 high severity vulnerabilities found')
      end
    end

    context 'when audit process fails' do
      before do
        allow(security_validator).to receive(:validate_production_security)
          .and_raise(StandardError, 'Security service unavailable')
      end

      it 'raises SecurityAuditError' do
        expect { subject.security_audit }
          .to raise_error(TcfPlatform::Monitoring::SecurityAuditError,
                         'Security audit failed: Security service unavailable')
      end
    end
  end

  describe '#real_time_alerts' do
    context 'when monitoring is not running' do
      it 'returns empty array' do
        expect(subject.real_time_alerts).to eq([])
      end
    end

    context 'when monitoring is running' do
      before do
        allow(subject).to receive(:running?).and_return(true)
        allow(security_validator).to receive(:validate_production_security)
          .and_return({ valid: true })
      end

      it 'returns active alerts for unhealthy services' do
        # Mock unhealthy services
        allow(monitoring_service).to receive(:check_service_health) do |service|
          { healthy: service != 'personas' }
        end

        alerts = subject.real_time_alerts

        service_alert = alerts.find { |alert| alert[:type] == 'service_health' }
        expect(service_alert).not_to be_nil
        expect(service_alert[:message]).to include('personas')
        expect(service_alert[:severity]).to eq('warning')
      end

      it 'returns security alerts when validation fails' do
        allow(security_validator).to receive(:validate_production_security)
          .and_return({ valid: false, errors: ['Certificate expired'] })
        
        # Mock all services healthy to isolate security alert
        allow(monitoring_service).to receive(:check_service_health)
          .and_return({ healthy: true })

        alerts = subject.real_time_alerts

        security_alert = alerts.find { |alert| alert[:type] == 'security' }
        expect(security_alert).not_to be_nil
        expect(security_alert[:severity]).to eq('critical')
        expect(security_alert[:message]).to include('Certificate expired')
      end

      it 'returns resource alerts when thresholds exceeded' do
        # Mock all services healthy and security valid
        allow(monitoring_service).to receive(:check_service_health)
          .and_return({ healthy: true })

        # Configure high alert threshold to trigger alerts
        high_threshold_monitor = described_class.new(
          monitoring_service: monitoring_service,
          deployment_manager: deployment_manager,
          security_validator: security_validator,
          backup_manager: backup_manager,
          config: { alert_threshold: 0.70 } # Lower threshold
        )
        allow(high_threshold_monitor).to receive(:running?).and_return(true)

        alerts = high_threshold_monitor.real_time_alerts

        resource_alerts = alerts.select { |alert| alert[:type] == 'resource' }
        expect(resource_alerts.size).to be >= 1
        expect(resource_alerts.first[:severity]).to eq('warning')
      end
    end
  end

  describe '#validate_deployment' do
    let(:version) { 'v2.1.0' }
    let(:readiness_result) { { overall_status: 'ready' } }

    before do
      allow(deployment_manager).to receive(:validate_production_readiness)
        .and_return(readiness_result)
    end

    context 'when system is ready for deployment' do
      it 'validates deployment successfully' do
        result = subject.validate_deployment(version)

        expect(result[:status]).to eq('validation_passed')
        expect(result[:version]).to eq(version)
        expect(result[:deployment_allowed]).to be true
        expect(result[:readiness]).to eq(readiness_result)
        expect(result[:validation_timestamp]).to be_a(Integer)
      end

      it 'includes resource and dependency checks' do
        result = subject.validate_deployment(version)

        expect(result[:resource_check]).to be_a(Hash)
        expect(result[:dependency_check]).to be_a(Hash)
        expect(result[:resource_check][:sufficient]).to be true
        expect(result[:dependency_check][:all_available]).to be true
      end
    end

    context 'when system is not ready for deployment' do
      let(:readiness_result) { { overall_status: 'not_ready' } }

      it 'fails validation' do
        result = subject.validate_deployment(version)

        expect(result[:status]).to eq('validation_failed')
        expect(result[:deployment_allowed]).to be false
      end
    end

    context 'when validation process fails' do
      before do
        allow(deployment_manager).to receive(:validate_production_readiness)
          .and_raise(StandardError, 'Validation service down')
      end

      it 'returns validation error' do
        result = subject.validate_deployment(version)

        expect(result[:status]).to eq('validation_error')
        expect(result[:error]).to eq('Validation service down')
        expect(result[:deployment_allowed]).to be false
      end
    end
  end

  describe '#monitor_deployment' do
    let(:deployment_id) { 'deploy-v2.1.0-1234567890' }

    context 'when production monitoring is running' do
      before do
        allow(subject).to receive(:running?).and_return(true)
        allow(monitoring_service).to receive(:check_service_health)
          .and_return({ healthy: true })
      end

      it 'monitors deployment with all services healthy' do
        result = subject.monitor_deployment(deployment_id)

        expect(result[:deployment_id]).to eq(deployment_id)
        expect(result[:start_time]).to be_a(Integer)
        expect(result[:services_status]).to be_a(Hash)
        expect(result[:overall_health]).to eq('healthy')
        expect(result[:monitoring_active]).to be true
      end

      it 'checks all TCF services' do
        services = %w[gateway personas workflows projects context tokens]
        
        services.each do |service|
          expect(monitoring_service).to receive(:check_service_health).with(service)
        end

        subject.monitor_deployment(deployment_id)
      end

      it 'detects unhealthy services' do
        allow(monitoring_service).to receive(:check_service_health) do |service|
          { healthy: service != 'workflows' }
        end

        result = subject.monitor_deployment(deployment_id)

        expect(result[:overall_health]).to eq('unhealthy')
        expect(result[:services_status]['workflows'][:healthy]).to be false
      end
    end

    context 'when production monitoring is not running' do
      before do
        allow(subject).to receive(:running?).and_return(false)
      end

      it 'returns error message' do
        result = subject.monitor_deployment(deployment_id)
        expect(result[:error]).to eq('Production monitoring not running')
      end
    end
  end

  describe '#running?' do
    it 'returns false when not started' do
      expect(subject.running?).to be false
    end

    it 'returns true after starting' do
      allow(monitoring_service).to receive(:running?).and_return(false)
      allow(monitoring_service).to receive(:start)
      
      subject.start_production_monitoring
      expect(subject.running?).to be true
    end
  end

  describe 'private methods' do
    describe '#collect_service_health_metrics' do
      before do
        allow(monitoring_service).to receive(:check_service_health) do |service|
          # Make personas and workflows unhealthy, others healthy
          { healthy: !%w[personas workflows].include?(service) }
        end
      end

      it 'collects health status for all services' do
        result = subject.send(:collect_service_health_metrics)

        expect(result[:all_services_healthy]).to be false
        expect(result[:critical_services_healthy]).to be true # gateway, postgres, redis are healthy
        expect(result[:unhealthy_services]).to include('personas', 'workflows')
        expect(result[:healthy_services]).to include('gateway', 'projects', 'context', 'tokens')
        expect(result[:total_services]).to eq(6)
      end
    end

    describe '#perform_vulnerability_scan' do
      it 'returns vulnerability scan results' do
        result = subject.send(:perform_vulnerability_scan)

        expect(result[:total_vulnerabilities]).to be_a(Integer)
        expect(result[:high_severity_count]).to be_a(Integer)
        expect(result[:medium_severity_count]).to be_a(Integer)
        expect(result[:low_severity_count]).to be_a(Integer)
        expect(result[:scan_timestamp]).to be_a(Integer)
      end
    end

    describe '#perform_compliance_check' do
      it 'returns compliance check results' do
        result = subject.send(:perform_compliance_check)

        expect(result[:compliant]).to be true
        expect(result[:violations]).to be_an(Array)
        expect(result[:checks_performed]).to be > 0
        expect(result[:check_timestamp]).to be_a(Integer)
      end
    end

    describe '#check_resource_thresholds' do
      context 'with high threshold config' do
        let(:config) { { alert_threshold: 0.90 } }

        it 'returns no alerts when usage is below threshold' do
          alerts = subject.send(:check_resource_thresholds)
          expect(alerts).to be_empty
        end
      end

      context 'with low threshold config' do
        let(:config) { { alert_threshold: 0.70 } }

        it 'returns resource alerts when usage exceeds threshold' do
          alerts = subject.send(:check_resource_thresholds)
          
          expect(alerts.size).to be >= 1
          resource_alert = alerts.first
          expect(resource_alert[:type]).to eq('resource')
          expect(resource_alert[:severity]).to eq('warning')
          expect(resource_alert[:message]).to include('usage:')
        end
      end
    end
  end
end