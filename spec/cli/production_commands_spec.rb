# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/cli/platform_cli'

RSpec.describe TcfPlatform::CLI do
  let(:cli) { described_class.new }
  let(:production_monitor) { instance_double(TcfPlatform::Monitoring::ProductionMonitor) }
  let(:deployment_manager) { instance_double(TcfPlatform::DeploymentManager) }
  let(:blue_green_deployer) { instance_double(TcfPlatform::BlueGreenDeployer) }

  before do
    allow(cli).to receive(:create_production_monitor).and_return(production_monitor)
    allow(cli).to receive(:deployment_manager).and_return(deployment_manager)
    allow(cli).to receive(:create_blue_green_deployer).and_return(blue_green_deployer)
    allow(production_monitor).to receive(:running?).and_return(false)
    allow(production_monitor).to receive(:monitoring_service).and_return(double(start_dashboard: { url: 'http://localhost:3006' }))
    
    # Suppress output during tests
    allow($stdout).to receive(:puts)
    allow($stdout).to receive(:print)
    allow($stdin).to receive(:gets).and_return("y\n")
  end

  describe '#prod_deploy' do
    let(:version) { 'v2.1.0' }
    let(:monitor_start_result) { { status: 'started', alerts_configured: 15 } }
    let(:backup_result) { { status: 'success', backup_id: 'backup-123' } }
    let(:validation_result) { { deployment_allowed: true, status: 'validation_passed' } }
    let(:deployment_result) do
      {
        overall_status: 'success',
        deployment: { 
          deployment_time: Time.now.to_i,
          services_deployed: 6,
          rollback_ready: true
        }
      }
    end
    let(:monitor_deployment_result) { { overall_health: 'healthy' } }

    before do
      allow(production_monitor).to receive(:start_production_monitoring).and_return(monitor_start_result)
      allow(cli).to receive(:create_deployment_backup).and_return(backup_result)
      allow(production_monitor).to receive(:validate_deployment).and_return(validation_result)
      allow(deployment_manager).to receive(:deploy_to_production).and_return(deployment_result)
      allow(production_monitor).to receive(:monitor_deployment).and_return(monitor_deployment_result)
    end

    context 'with default options' do
      before do
        cli.options = { environment: 'production', strategy: 'blue_green', backup: true, validate: true, force: false }
      end

      it 'executes complete production deployment workflow' do
        aggregate_failures do
          expect(production_monitor).to receive(:start_production_monitoring)
          expect(cli).to receive(:create_deployment_backup).with(version)
          expect(production_monitor).to receive(:validate_deployment).with(version)
          expect(deployment_manager).to receive(:deploy_to_production)
          expect(production_monitor).to receive(:monitor_deployment)
        end

        cli.prod_deploy(version)
      end

      it 'displays deployment progress and success' do
        expect($stdout).to receive(:puts).with("🚀 Starting production deployment for version #{version}")
        expect($stdout).to receive(:puts).with("✅ Production monitoring started")
        expect($stdout).to receive(:puts).with("✅ Backup created: backup-123")
        expect($stdout).to receive(:puts).with("✅ Pre-deployment validation passed")
        expect($stdout).to receive(:puts).with("✅ Production deployment successful!")

        cli.prod_deploy(version)
      end
    end

    context 'when backup fails and force is false' do
      let(:backup_result) { { status: 'failed', error: 'Disk full' } }

      before do
        cli.options = { backup: true, force: false }
      end

      it 'stops deployment process' do
        expect(cli).to receive(:create_deployment_backup).and_return(backup_result)
        expect(deployment_manager).not_to receive(:deploy_to_production)
        expect($stdout).to receive(:puts).with("⚠️  Backup failed: Disk full")

        cli.prod_deploy(version)
      end
    end

    context 'when validation fails and force is false' do
      let(:validation_result) { { deployment_allowed: false, status: 'validation_failed' } }

      before do
        cli.options = { validate: true, force: false }
      end

      it 'stops deployment process' do
        expect(production_monitor).to receive(:validate_deployment).and_return(validation_result)
        expect(deployment_manager).not_to receive(:deploy_to_production)
        expect($stdout).to receive(:puts).with("❌ Deployment validation failed")

        cli.prod_deploy(version)
      end
    end

    context 'when deployment fails' do
      let(:deployment_result) do
        {
          overall_status: 'failed',
          deployment: { error: 'Service startup timeout' }
        }
      end

      before do
        cli.options = { backup: false, validate: false }
      end

      it 'displays deployment failure' do
        expect($stdout).to receive(:puts).with("❌ Production deployment failed")
        cli.prod_deploy(version)
      end
    end

    context 'when force option is true' do
      before do
        cli.options = { backup: true, validate: true, force: true }
      end

      it 'continues deployment despite backup failure' do
        allow(cli).to receive(:create_deployment_backup).and_return({ status: 'failed', error: 'Error' })
        
        expect(deployment_manager).to receive(:deploy_to_production)
        cli.prod_deploy(version)
      end

      it 'continues deployment despite validation failure' do
        allow(production_monitor).to receive(:validate_deployment)
          .and_return({ deployment_allowed: false, status: 'validation_failed' })
        
        expect(deployment_manager).to receive(:deploy_to_production)
        cli.prod_deploy(version)
      end
    end
  end

  describe '#prod_rollback' do
    let(:version) { 'v2.0.0' }
    let(:rollback_result) do
      {
        status: 'success',
        rollback_time: Time.now.to_i,
        rolled_back_to: version
      }
    end
    let(:health_result) { { overall_status: 'healthy' } }

    before do
      allow(blue_green_deployer).to receive(:rollback).and_return(rollback_result)
      allow(production_monitor).to receive(:deployment_health_status).and_return(health_result)
    end

    context 'rolling back to specific version' do
      before do
        cli.options = { to_version: version, reason: 'Critical bug found', force: true }
      end

      it 'executes rollback for all services' do
        services = %w[gateway personas workflows projects context tokens]
        
        services.each do |service|
          expect(blue_green_deployer).to receive(:rollback).with(
            service,
            reason: 'Critical bug found',
            version: version,
            manual: true
          ).and_return(rollback_result)
        end

        cli.prod_rollback
      end

      it 'displays rollback progress and success' do
        expect($stdout).to receive(:puts).with("🔄 Rolling back production deployment")
        expect($stdout).to receive(:puts).with("✅ Production rollback successful!")

        cli.prod_rollback
      end
    end

    context 'rolling back specific service' do
      before do
        cli.options = { service: 'gateway', force: true, reason: 'Gateway issues' }
      end

      it 'rolls back only specified service' do
        expect(blue_green_deployer).to receive(:rollback).with(
          'gateway',
          reason: 'Gateway issues',
          version: nil,
          manual: true
        ).and_return(rollback_result)

        cli.prod_rollback
      end
    end

    context 'when rollback fails' do
      let(:rollback_result) do
        {
          status: 'failed',
          error: 'Traffic switch failed',
          manual_intervention_required: true
        }
      end

      before do
        cli.options = { force: true }
      end

      it 'displays failure and manual intervention message' do
        expect($stdout).to receive(:puts).with("❌ Production rollback failed")
        expect($stdout).to receive(:puts).with("⚠️  Manual intervention required")

        cli.prod_rollback
      end
    end

    context 'without force option' do
      before do
        cli.options = { force: false }
        allow($stdin).to receive(:gets).and_return("n\n")
      end

      it 'prompts for confirmation and cancels on no' do
        expect($stdout).to receive(:print).with("Are you sure you want to continue? (y/N): ")
        expect($stdout).to receive(:puts).with("Rollback cancelled")
        expect(blue_green_deployer).not_to receive(:rollback)

        cli.prod_rollback
      end
    end
  end

  describe '#prod_status' do
    let(:health_status) do
      {
        overall_status: 'healthy',
        timestamp: Time.now.to_i,
        service_health: {
          all_services_healthy: true,
          healthy_count: 6,
          total_services: 6,
          healthy_services: %w[gateway personas workflows projects context tokens],
          unhealthy_services: []
        },
        security_status: { valid: true },
        deployment_readiness: {
          overall_status: 'ready',
          infrastructure: { all_ready: true },
          services: { all_healthy: true, tests_passing: true, security_scans: { status: 'passed' } }
        }
      }
    end

    before do
      allow(production_monitor).to receive(:deployment_health_status).and_return(health_status)
      cli.options = { services: false, health: false, metrics: false, format: 'table' }
    end

    it 'displays overall production status' do
      expect($stdout).to receive(:puts).with("📊 TCF Platform Production Status")
      expect($stdout).to receive(:puts).with("Overall Status: ✅ HEALTHY")

      cli.prod_status
    end

    context 'with services option' do
      before do
        cli.options = { services: true }
      end

      it 'displays detailed service health information' do
        expect($stdout).to receive(:puts).with("🔧 Service Health:")
        expect($stdout).to receive(:puts).with("  Healthy Services (6/6):")
        expect($stdout).to receive(:puts).with("    ✅ gateway")

        cli.prod_status
      end
    end

    context 'with health option' do
      before do
        cli.options = { health: true }
      end

      it 'displays health metrics' do
        expect($stdout).to receive(:puts).with("🏥 Health Metrics:")
        expect($stdout).to receive(:puts).with("  Infrastructure: Ready")
        expect($stdout).to receive(:puts).with("  Services: Healthy")

        cli.prod_status
      end
    end

    context 'with metrics option' do
      before do
        cli.options = { metrics: true }
      end

      it 'displays performance metrics' do
        expect($stdout).to receive(:puts).with("📈 Performance Metrics:")
        expect($stdout).to receive(:puts).with("  System Load: 65.2%")

        cli.prod_status
      end
    end

    context 'with json format' do
      before do
        cli.options = { format: 'json' }
      end

      it 'displays JSON output' do
        expect($stdout).to receive(:puts).with("Raw JSON Data:")
        expect($stdout).to receive(:puts).with(JSON.pretty_generate(health_status))

        cli.prod_status
      end
    end

    context 'when unhealthy services exist' do
      let(:health_status) do
        {
          overall_status: 'degraded',
          service_health: {
            unhealthy_services: ['personas'],
            healthy_services: %w[gateway workflows projects context tokens]
          },
          security_status: { valid: true }
        }
      end

      before do
        cli.options = { services: true }
      end

      it 'displays unhealthy services' do
        expect($stdout).to receive(:puts).with("Overall Status: ⚠️  DEGRADED")
        expect($stdout).to receive(:puts).with("  Unhealthy Services:")
        expect($stdout).to receive(:puts).with("    ❌ personas")

        cli.prod_status
      end
    end
  end

  describe '#prod_audit' do
    let(:audit_result) do
      {
        audit_status: 'passed',
        audit_timestamp: Time.now.to_i,
        critical_issues: [],
        warnings: [],
        vulnerability_scan: {
          total_vulnerabilities: 3,
          high_severity_count: 0,
          medium_severity_count: 2,
          low_severity_count: 1
        },
        compliance_check: {
          compliant: true,
          checks_performed: 15
        },
        access_audit: {
          users_audited: 25,
          privileged_accounts: 3,
          inactive_accounts: 2
        }
      }
    end

    before do
      allow(production_monitor).to receive(:security_audit).and_return(audit_result)
      cli.options = { comprehensive: false, format: 'table' }
    end

    it 'displays audit status and results' do
      expect($stdout).to receive(:puts).with("🔒 Running Production Security Audit")
      expect($stdout).to receive(:puts).with("Audit Status: ✅ PASSED")

      cli.prod_audit
    end

    context 'with critical issues' do
      let(:audit_result) do
        {
          audit_status: 'failed',
          critical_issues: ['SSL certificate expired', 'Weak passwords detected'],
          warnings: ['Outdated dependency']
        }
      end

      it 'displays critical issues and warnings' do
        expect($stdout).to receive(:puts).with("Audit Status: ❌ FAILED")
        expect($stdout).to receive(:puts).with("🚨 Critical Issues:")
        expect($stdout).to receive(:puts).with("  • SSL certificate expired")
        expect($stdout).to receive(:puts).with("  • Weak passwords detected")
        expect($stdout).to receive(:puts).with("⚠️  Warnings:")
        expect($stdout).to receive(:puts).with("  • Outdated dependency")

        cli.prod_audit
      end
    end

    context 'with comprehensive option' do
      before do
        cli.options = { comprehensive: true }
      end

      it 'displays detailed vulnerability and compliance information' do
        expect($stdout).to receive(:puts).with("🔍 Vulnerability Scan:")
        expect($stdout).to receive(:puts).with("  Total Vulnerabilities: 3")
        expect($stdout).to receive(:puts).with("  High Severity: 0")
        expect($stdout).to receive(:puts).with("📋 Compliance Check: ✅ COMPLIANT")
        expect($stdout).to receive(:puts).with("👥 Access Control Audit:")

        cli.prod_audit
      end
    end

    context 'with output file option' do
      before do
        cli.options = { output: '/tmp/audit_report.txt' }
        allow(cli).to receive(:save_audit_report)
      end

      it 'saves audit report to file' do
        expect(cli).to receive(:save_audit_report).with(audit_result, '/tmp/audit_report.txt')
        expect($stdout).to receive(:puts).with("📄 Audit report saved to: /tmp/audit_report.txt")

        cli.prod_audit
      end
    end

    context 'when audit fails' do
      before do
        allow(production_monitor).to receive(:security_audit)
          .and_raise(TcfPlatform::Monitoring::SecurityAuditError, 'Audit service unavailable')
      end

      it 'displays error message' do
        expect($stdout).to receive(:puts).with("❌ Security audit failed: Audit service unavailable")
        cli.prod_audit
      end
    end
  end

  describe '#prod_validate' do
    let(:validation_result) do
      {
        status: 'validation_passed',
        version: 'v2.1.0',
        deployment_allowed: true,
        readiness: {
          overall_status: 'ready',
          security: { valid: true },
          infrastructure: { all_ready: true },
          services: { all_healthy: true }
        },
        resource_check: {
          sufficient: true,
          cpu_available: 85.5,
          memory_available: 78.2,
          disk_available: 65.8
        },
        dependency_check: {
          all_available: true,
          available_dependencies: %w[postgres redis],
          unavailable_dependencies: []
        }
      }
    end

    before do
      allow(production_monitor).to receive(:validate_deployment).and_return(validation_result)
      cli.options = { version: 'v2.1.0', check_dependencies: true, security_scan: true, format: 'table' }
    end

    it 'displays validation status and readiness information' do
      expect($stdout).to receive(:puts).with("🔍 Validating Production Readiness")
      expect($stdout).to receive(:puts).with("Validation Status: ✅ VALIDATION_PASSED")
      expect($stdout).to receive(:puts).with("🚀 Deployment Readiness:")
      expect($stdout).to receive(:puts).with("  Overall: ready")

      cli.prod_validate
    end

    it 'displays resource availability' do
      expect($stdout).to receive(:puts).with("💾 Resource Availability:")
      expect($stdout).to receive(:puts).with("  Sufficient Resources: Yes")
      expect($stdout).to receive(:puts).with("  CPU Available: 85.5%")

      cli.prod_validate
    end

    context 'with check_dependencies option' do
      it 'displays dependency status' do
        expect($stdout).to receive(:puts).with("🔗 External Dependencies:")
        expect($stdout).to receive(:puts).with("  All Available: Yes")

        cli.prod_validate
      end
    end

    context 'with security_scan option' do
      it 'displays security status' do
        expect($stdout).to receive(:puts).with("🔒 Security Status:")
        expect($stdout).to receive(:puts).with("  Production Security: Valid")

        cli.prod_validate
      end
    end

    context 'when validation fails' do
      let(:validation_result) do
        {
          status: 'validation_failed',
          deployment_allowed: false,
          readiness: { overall_status: 'not_ready' }
        }
      end

      it 'displays failure and recommendation' do
        expect($stdout).to receive(:puts).with("❌ PRODUCTION DEPLOYMENT NOT RECOMMENDED")
        expect($stdout).to receive(:puts).with("   Please resolve issues before deploying")

        cli.prod_validate
      end
    end

    context 'with json format' do
      before do
        cli.options = { format: 'json' }
      end

      it 'displays JSON output' do
        expect($stdout).to receive(:puts).with("Raw JSON Data:")
        expect($stdout).to receive(:puts).with(JSON.pretty_generate(validation_result))

        cli.prod_validate
      end
    end
  end

  describe '#prod_monitor' do
    let(:start_result) { { status: 'started', start_time: Time.now.to_i, alerts_configured: 15 } }
    let(:stop_result) { { uptime_seconds: 3600, alerts_processed: 5 } }
    let(:health_status) do
      {
        overall_status: 'healthy',
        service_health: { total_services: 6, healthy_count: 6 }
      }
    end

    before do
      allow(production_monitor).to receive(:start_production_monitoring).and_return(start_result)
      allow(production_monitor).to receive(:stop_production_monitoring).and_return(stop_result)
      allow(production_monitor).to receive(:deployment_health_status).and_return(health_status)
    end

    context 'start action' do
      before do
        cli.options = { action: 'start' }
      end

      it 'starts production monitoring' do
        expect(production_monitor).to receive(:start_production_monitoring)
        expect($stdout).to receive(:puts).with("✅ Production monitoring started successfully")

        cli.prod_monitor
      end

      context 'when already running' do
        before do
          allow(production_monitor).to receive(:running?).and_return(true)
        end

        it 'displays already running message' do
          expect($stdout).to receive(:puts).with("⚠️  Production monitoring is already running")
          cli.prod_monitor
        end
      end
    end

    context 'stop action' do
      before do
        cli.options = { action: 'stop' }
        allow(production_monitor).to receive(:running?).and_return(true)
      end

      it 'stops production monitoring' do
        expect(production_monitor).to receive(:stop_production_monitoring)
        expect($stdout).to receive(:puts).with("✅ Production monitoring stopped")

        cli.prod_monitor
      end
    end

    context 'restart action' do
      before do
        cli.options = { action: 'restart' }
        allow(production_monitor).to receive(:running?).and_return(true)
      end

      it 'restarts production monitoring' do
        expect(production_monitor).to receive(:stop_production_monitoring)
        expect(production_monitor).to receive(:start_production_monitoring).and_return(start_result)
        expect($stdout).to receive(:puts).with("✅ Production monitoring restarted successfully")

        cli.prod_monitor
      end
    end

    context 'status action' do
      before do
        cli.options = { action: 'status' }
        allow(production_monitor).to receive(:running?).and_return(true)
      end

      it 'displays monitoring status' do
        expect($stdout).to receive(:puts).with("📊 Monitoring Status:")
        expect($stdout).to receive(:puts).with("  Running: Yes")
        expect($stdout).to receive(:puts).with("  Overall Health: healthy")

        cli.prod_monitor
      end
    end

    context 'with dashboard option' do
      let(:monitoring_service) { instance_double(TcfPlatform::Monitoring::MonitoringService) }
      let(:dashboard_result) { { url: 'http://localhost:3006' } }

      before do
        cli.options = { action: 'start', dashboard: true, port: 3006 }
        allow(production_monitor).to receive(:running?).and_return(true)
        allow(production_monitor).to receive(:monitoring_service).and_return(monitoring_service)
        allow(monitoring_service).to receive(:start_dashboard).and_return(dashboard_result)
      end

      it 'starts monitoring dashboard' do
        expect(monitoring_service).to receive(:start_dashboard).with(port: 3006)
        expect($stdout).to receive(:puts).with("✅ Dashboard available at: http://localhost:3006")

        cli.prod_monitor
      end
    end

    context 'with alerts option' do
      let(:active_alerts) do
        [
          {
            type: 'service_health',
            severity: 'warning',
            message: 'High response time detected',
            timestamp: Time.now.to_i
          },
          {
            type: 'security',
            severity: 'critical',
            message: 'Unauthorized access attempt',
            timestamp: Time.now.to_i
          }
        ]
      end

      before do
        cli.options = { action: 'status', alerts: true }
        allow(production_monitor).to receive(:real_time_alerts).and_return(active_alerts)
      end

      it 'displays active alerts' do
        expect($stdout).to receive(:puts).with("🚨 Active Alerts:")
        expect($stdout).to receive(:puts).with(/⚠️.*High response time detected/)
        expect($stdout).to receive(:puts).with(/🔥.*Unauthorized access attempt/)

        cli.prod_monitor
      end
    end

    context 'with no active alerts' do
      before do
        cli.options = { action: 'status', alerts: true }
        allow(production_monitor).to receive(:real_time_alerts).and_return([])
      end

      it 'displays no alerts message' do
        expect($stdout).to receive(:puts).with("🚨 Active Alerts:")
        expect($stdout).to receive(:puts).with("  No active alerts")

        cli.prod_monitor
      end
    end

    context 'with unknown action' do
      before do
        cli.options = { action: 'unknown' }
      end

      it 'displays error for unknown action' do
        expect($stdout).to receive(:puts).with("❌ Unknown action: unknown")
        expect($stdout).to receive(:puts).with("Available actions: start, stop, restart, status")

        cli.prod_monitor
      end
    end
  end

  describe 'helper methods' do
    describe '#create_production_monitor' do
      it 'creates ProductionMonitor with all required dependencies' do
        result = cli.send(:create_production_monitor)
        expect(result).to be_a(TcfPlatform::Monitoring::ProductionMonitor)
      end
    end

    describe '#create_blue_green_deployer' do
      it 'creates BlueGreenDeployer with required dependencies' do
        result = cli.send(:create_blue_green_deployer)
        expect(result).to be_a(TcfPlatform::BlueGreenDeployer)
      end
    end

    describe '#build_deployment_config' do
      let(:version) { 'v2.1.0' }

      before do
        cli.options = { environment: 'production', strategy: 'blue_green' }
      end

      it 'builds deployment configuration hash' do
        result = cli.send(:build_deployment_config, version)

        expect(result[:version]).to eq(version)
        expect(result[:environment]).to eq('production')
        expect(result[:strategy]).to eq('blue_green')
        expect(result[:services]).to include('gateway', 'personas', 'workflows')
        expect(result[:replicas]['gateway']).to eq(2)
      end
    end

    describe '#save_audit_report' do
      let(:audit_result) do
        {
          audit_status: 'passed',
          critical_issues: [],
          audit_timestamp: Time.now.to_i,
          warnings: [],
          vulnerability_scan: {
            total_vulnerabilities: 0,
            high_severity_count: 0,
            medium_severity_count: 0,
            low_severity_count: 0
          }
        }
      end

      before do
        allow(File).to receive(:write)
      end

      context 'with JSON extension' do
        it 'saves audit report as JSON' do
          expect(File).to receive(:write).with(
            '/tmp/audit.json',
            JSON.pretty_generate(audit_result)
          )

          cli.send(:save_audit_report, audit_result, '/tmp/audit.json')
        end
      end

      context 'with text extension' do
        it 'saves audit report as formatted text' do
          expect(File).to receive(:write) do |filename, content|
            expect(filename).to eq('/tmp/audit.txt')
            expect(content).to include('TCF Platform Security Audit Report')
            expect(content).to include('Status: passed')
          end

          cli.send(:save_audit_report, audit_result, '/tmp/audit.txt')
        end
      end
    end
  end

  describe 'error handling' do
    context 'when production monitor creation fails' do
      before do
        allow(cli).to receive(:create_production_monitor)
          .and_raise(StandardError, 'Monitor initialization failed')
        cli.options = {}
      end

      it 'handles deployment errors gracefully' do
        expect($stdout).to receive(:puts).with("❌ Unexpected error: Monitor initialization failed")
        cli.prod_deploy('v2.1.0')
      end

      it 'handles status errors gracefully' do
        expect($stdout).to receive(:puts).with("❌ Failed to get production status: Monitor initialization failed")
        cli.prod_status
      end

      it 'handles validation errors gracefully' do
        expect($stdout).to receive(:puts).with("❌ Validation error: Monitor initialization failed")
        cli.prod_validate
      end

      it 'handles monitoring management errors gracefully' do
        expect($stdout).to receive(:puts).with("❌ Monitoring management error: Monitor initialization failed")
        cli.prod_monitor
      end
    end
  end
end