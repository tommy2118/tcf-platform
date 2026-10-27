# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require_relative '../../lib/cli/platform_cli'
require_relative '../../lib/monitoring/production_monitor'
require_relative '../../lib/deployment_manager'
require_relative '../../lib/blue_green_deployer'

RSpec.describe 'Production Workflow Integration' do
  let(:cli) { TcfPlatform::CLI.new }
  let(:version) { 'v2.1.0' }
  
  # Mock dependencies for integration testing (avoid Redis connections)
  let(:config_manager) { instance_double(TcfPlatform::ConfigManager) }
  let(:docker_manager) { instance_double(TcfPlatform::DockerManager) }
  let(:monitoring_service) { instance_double(TcfPlatform::Monitoring::MonitoringService) }
  let(:security_validator) { instance_double(TcfPlatform::SecurityValidator) }
  let(:backup_manager) { instance_double(TcfPlatform::BackupManager) }
  let(:deployment_manager) { instance_double(TcfPlatform::DeploymentManager) }
  let(:production_monitor) { instance_double(TcfPlatform::Monitoring::ProductionMonitor) }

  before do
    # Suppress CLI output during integration tests
    allow($stdout).to receive(:puts)
    allow($stdout).to receive(:print)
    allow($stdin).to receive(:gets).and_return("y\n")

    # Mock docker manager
    allow(docker_manager).to receive(:verify_swarm_cluster).and_return({ status: 'healthy' })
    allow(docker_manager).to receive(:service_status).and_return({
      'gateway' => { status: 'healthy' },
      'personas' => { status: 'healthy' },
      'workflows' => { status: 'healthy' },
      'projects' => { status: 'healthy' },
      'context' => { status: 'healthy' },
      'tokens' => { status: 'healthy' }
    })
    allow(docker_manager).to receive(:create_service).and_return({ service_id: 'test-service-green' })
    allow(docker_manager).to receive(:wait_for_service_health).and_return({ healthy: true })
    allow(docker_manager).to receive(:get_service_status).and_return({
      blue: { status: 'healthy' },
      green: { status: 'healthy' }
    })

    # Mock backup manager
    allow(backup_manager).to receive(:verify_backup_system).and_return({ status: 'healthy' })
    allow(backup_manager).to receive(:create_backup).and_return({ 
      status: 'success', 
      backup_id: 'backup-123' 
    })

    # Mock monitoring service
    allow(monitoring_service).to receive(:running?).and_return(false)
    allow(monitoring_service).to receive(:start)
    allow(monitoring_service).to receive(:stop)
    allow(monitoring_service).to receive(:health_check).and_return({ status: 'healthy' })
    allow(monitoring_service).to receive(:check_service_health).and_return({ healthy: true })
    allow(monitoring_service).to receive(:validate_service_metrics).and_return({ status: 'healthy' })
    allow(monitoring_service).to receive(:enable_production_monitoring).and_return({
      status: 'success',
      dashboards_enabled: 5,
      alerts_configured: 15
    })
    allow(monitoring_service).to receive(:start_dashboard).and_return({ url: 'http://localhost:3006' })

    # Mock security validator
    allow(security_validator).to receive(:validate_production_security).and_return({ valid: true })

    # Mock deployment manager
    allow(deployment_manager).to receive(:deploy_to_production).and_return({
      overall_status: 'success',
      deployment: {
        deployment_time: Time.now.to_i,
        services_deployed: 6,
        rollback_ready: true
      }
    })
    allow(deployment_manager).to receive(:validate_production_readiness).and_return({
      overall_status: 'ready',
      security: { valid: true },
      infrastructure: { all_ready: true },
      services: { all_healthy: true, tests_passing: true, security_scans: { status: 'passed' } }
    })

    # Mock production monitor
    allow(production_monitor).to receive(:running?).and_return(false)
    allow(production_monitor).to receive(:start_production_monitoring).and_return({
      status: 'started',
      start_time: Time.now,
      alerts_configured: 15,
      health_checks_enabled: true
    })
    allow(production_monitor).to receive(:stop_production_monitoring).and_return({
      uptime_seconds: 3600,
      alerts_processed: 5
    })
    allow(production_monitor).to receive(:validate_deployment).and_return({
      deployment_allowed: true,
      status: 'validation_passed'
    })
    allow(production_monitor).to receive(:monitor_deployment).and_return({
      overall_health: 'healthy'
    })
    allow(production_monitor).to receive(:deployment_health_status).and_return({
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
    })
    allow(production_monitor).to receive(:security_audit).and_return({
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
    })
    allow(production_monitor).to receive(:real_time_alerts).and_return([])
    allow(production_monitor).to receive(:monitoring_service).and_return(monitoring_service)

    # Override CLI dependency creation to use mocked objects
    allow(cli).to receive(:create_production_monitor).and_return(production_monitor)
    allow(cli).to receive(:deployment_manager).and_return(deployment_manager)
  end

  describe 'Complete Production Deployment Workflow' do
    it 'executes end-to-end production deployment successfully' do
      # Set CLI options for deployment
      cli.options = { 
        environment: 'production', 
        strategy: 'blue_green', 
        backup: true, 
        validate: true, 
        force: false 
      }

      aggregate_failures 'production deployment workflow' do
        # Production monitoring should start
        expect(production_monitor).to receive(:start_production_monitoring)

        # Backup should be created via CLI create_deployment_backup method
        expect(cli).to receive(:create_deployment_backup).with(version).and_return({ 
          status: 'success', 
          backup_id: 'backup-123' 
        })

        # Validation should pass
        expect(production_monitor).to receive(:validate_deployment).with(version)

        # Deployment should execute
        expect(deployment_manager).to receive(:deploy_to_production)

        # Post-deployment monitoring should occur
        expect(production_monitor).to receive(:monitor_deployment)

        # Execute the deployment
        cli.prod_deploy(version)
      end
    end

    it 'handles deployment failure gracefully with proper error reporting' do
      cli.options = { backup: false, validate: false, force: false }

      # Mock deployment failure
      allow(deployment_manager).to receive(:deploy_to_production)
        .and_return({ overall_status: 'failed', deployment: { error: 'Service startup failed' } })

      # Should handle error gracefully
      expect { cli.prod_deploy(version) }.not_to raise_error

      # Should display error message
      expect($stdout).to have_received(:puts).with("❌ Production deployment failed")
    end
  end

  describe 'Production Rollback Workflow' do
    let(:rollback_result) do
      {
        status: 'success',
        rollback_time: Time.now.to_i,
        rolled_back_to: 'v2.0.0'
      }
    end

    before do
      # Mock blue-green deployer
      blue_green_deployer = instance_double(TcfPlatform::BlueGreenDeployer)
      allow(blue_green_deployer).to receive(:rollback).and_return(rollback_result)
      allow(cli).to receive(:create_blue_green_deployer).and_return(blue_green_deployer)
    end

    it 'executes end-to-end production rollback successfully' do
      cli.options = { to_version: 'v2.0.0', reason: 'Critical bug', force: true }

      aggregate_failures 'production rollback workflow' do
        # Should rollback all services
        blue_green_deployer = cli.send(:create_blue_green_deployer)
        services = %w[gateway personas workflows projects context tokens]
        services.each do |service|
          expect(blue_green_deployer).to receive(:rollback).with(
            service,
            reason: 'Critical bug',
            version: 'v2.0.0',
            manual: true
          ).and_return(rollback_result)
        end

        # Should check post-rollback health
        expect(production_monitor).to receive(:deployment_health_status)

        # Execute rollback
        cli.prod_rollback

        # Should display success message
        expect($stdout).to have_received(:puts).with("✅ Production rollback successful!")
      end
    end

    it 'handles rollback confirmation workflow' do
      cli.options = { force: false }
      
      # Mock user confirmation process
      allow(cli).to receive(:confirm_rollback).and_return(true)

      # Should execute rollback after confirmation
      blue_green_deployer = cli.send(:create_blue_green_deployer)
      expect(blue_green_deployer).to receive(:rollback).at_least(:once).and_return(rollback_result)

      cli.prod_rollback
    end
  end

  describe 'Production Monitoring Workflow' do
    it 'manages complete monitoring lifecycle' do
      # Set up state changes for lifecycle
      allow(production_monitor).to receive(:running?).and_return(false, true, true, false)
      
      aggregate_failures 'monitoring lifecycle' do
        # Start monitoring
        cli.options = { action: 'start' }
        expect { cli.prod_monitor }.not_to raise_error

        # Check status
        cli.options = { action: 'status' }
        expect { cli.prod_monitor }.not_to raise_error

        # Stop monitoring
        cli.options = { action: 'stop' }
        expect { cli.prod_monitor }.not_to raise_error
      end
    end

    it 'handles dashboard management' do
      cli.options = { action: 'start', dashboard: true, port: 3006 }

      # Set up monitoring state changes: not running initially, then running after start
      allow(production_monitor).to receive(:running?).and_return(false, true)

      # Mock dashboard start
      dashboard_result = { url: 'http://localhost:3006' }
      expect(monitoring_service).to receive(:start_dashboard).with(port: 3006).and_return(dashboard_result)

      cli.prod_monitor

      expect($stdout).to have_received(:puts).with("✅ Dashboard available at: http://localhost:3006")
    end
  end

  describe 'Production Audit Workflow' do
    it 'executes comprehensive security audit' do
      cli.options = { comprehensive: true, format: 'table' }

      # Should execute audit successfully
      expect { cli.prod_audit }.not_to raise_error

      # Should display audit results
      expect($stdout).to have_received(:puts).with("🔒 Running Production Security Audit")
      expect($stdout).to have_received(:puts).with(/Audit Status:.*PASSED/)
    end

    it 'saves audit report to file' do
      cli.options = { output: '/tmp/test_audit.json', format: 'json' }
      
      # Mock file writing
      allow(File).to receive(:write)
      
      cli.prod_audit

      expect(File).to have_received(:write) do |filename, content|
        expect(filename).to eq('/tmp/test_audit.json')
        expect { JSON.parse(content) }.not_to raise_error
      end
    end
  end

  describe 'Production Validation Workflow' do
    it 'validates production readiness comprehensively' do
      cli.options = { 
        version: version, 
        check_dependencies: true, 
        security_scan: true, 
        format: 'table' 
      }

      # Should execute validation successfully
      expect { cli.prod_validate }.not_to raise_error

      # Should display validation results
      expect($stdout).to have_received(:puts).with("🔍 Validating Production Readiness")
      expect($stdout).to have_received(:puts).with(/Validation Status:.*VALIDATION_PASSED/)
      expect($stdout).to have_received(:puts).with("✅ PRODUCTION DEPLOYMENT APPROVED")
    end

    it 'handles validation failure scenarios' do
      # Mock validation failure
      allow(production_monitor).to receive(:validate_deployment).and_return({
        status: 'validation_failed',
        version: version,
        deployment_allowed: false,
        readiness: { 
          overall_status: 'not_ready',
          security: { valid: false, errors: ['SSL certificate expired'] },
          infrastructure: { all_ready: false },
          services: { all_healthy: false }
        },
        resource_check: {
          sufficient: false,
          cpu_available: 15.2,
          memory_available: 8.1,
          disk_available: 92.3
        },
        dependency_check: {
          all_available: true,
          available_dependencies: %w[postgres redis],
          unavailable_dependencies: []
        },
        validation_timestamp: Time.now.to_i
      })

      cli.options = { version: version }

      cli.prod_validate

      expect($stdout).to have_received(:puts).with("❌ PRODUCTION DEPLOYMENT NOT RECOMMENDED")
    end
  end

  describe 'Error Handling and Recovery' do
    it 'handles ProductionMonitorError gracefully' do
      allow(cli).to receive(:create_production_monitor)
        .and_raise(TcfPlatform::Monitoring::ProductionMonitorError, 'Monitor failed to initialize')

      cli.options = {}

      expect { cli.prod_deploy(version) }.not_to raise_error
      expect($stdout).to have_received(:puts).with(/❌.*Monitor failed to initialize/)
    end

    it 'handles SecurityAuditError gracefully' do
      allow(production_monitor).to receive(:security_audit)
        .and_raise(TcfPlatform::Monitoring::SecurityAuditError, 'Security service down')

      cli.options = {}

      expect { cli.prod_audit }.not_to raise_error
      expect($stdout).to have_received(:puts).with("❌ Security audit failed: Security service down")
    end

    it 'provides helpful error messages for common issues' do
      # Test deployment failure with specific error handling
      allow(deployment_manager).to receive(:deploy_to_production)
        .and_raise(TcfPlatform::ProductionDeploymentError, 'SSL certificates not configured')

      cli.options = { backup: false, validate: false }

      cli.prod_deploy(version)

      expect($stdout).to have_received(:puts).with("❌ Production deployment error: SSL certificates not configured")
    end
  end

  describe 'Production Status Integration' do
    it 'displays comprehensive production status information' do
      cli.options = { services: true, health: true, metrics: true, format: 'table' }

      # Should execute without errors
      expect { cli.prod_status }.not_to raise_error

      # Should display all requested information sections
      expect($stdout).to have_received(:puts).with("📊 TCF Platform Production Status")
      expect($stdout).to have_received(:puts).with(/Overall Status:.*HEALTHY/)
      expect($stdout).to have_received(:puts).with("🔧 Service Health:")
      expect($stdout).to have_received(:puts).with("🏥 Health Metrics:")
      expect($stdout).to have_received(:puts).with("📈 Performance Metrics:")
    end

    it 'handles degraded system status appropriately' do
      # Mock degraded status
      allow(production_monitor).to receive(:deployment_health_status).and_return({
        overall_status: 'degraded',
        timestamp: Time.now.to_i,
        service_health: {
          unhealthy_services: ['personas'],
          healthy_services: %w[gateway workflows projects context tokens],
          healthy_count: 5,
          total_services: 6
        },
        security_status: { valid: true }
      })

      cli.options = { services: true }

      cli.prod_status

      expect($stdout).to have_received(:puts).with(/Overall Status:.*DEGRADED/)
    end
  end

  describe 'CLI Command Integration' do
    it 'includes production commands in help output' do
      # Capture help output
      captured_output = StringIO.new
      allow($stdout).to receive(:puts) { |str| captured_output.puts(str) }
      cli.help
      output = captured_output.string

      aggregate_failures 'production commands in help' do
        expect(output).to include('Production Commands:')
        expect(output).to include('tcf-platform prod deploy VERSION')
        expect(output).to include('tcf-platform prod rollback [VER]')
        expect(output).to include('tcf-platform prod status')
        expect(output).to include('tcf-platform prod audit')
        expect(output).to include('tcf-platform prod validate')
        expect(output).to include('tcf-platform prod monitor')
      end
    end

    it 'supports all documented production command options' do
      # Test that all documented options are supported without errors
      
      # Deploy command options
      cli.options = { 
        environment: 'staging', 
        strategy: 'rolling', 
        backup: false, 
        validate: false, 
        force: true 
      }
      expect { cli.prod_deploy(version) }.not_to raise_error

      # Rollback command options
      cli.options = { 
        to_version: 'v2.0.0', 
        reason: 'Test rollback', 
        force: true, 
        service: 'gateway' 
      }
      expect { cli.prod_rollback }.not_to raise_error

      # Status command options
      cli.options = { 
        services: true, 
        health: true, 
        metrics: true, 
        format: 'json' 
      }
      expect { cli.prod_status }.not_to raise_error

      # Audit command options
      cli.options = { 
        comprehensive: true, 
        output: '/tmp/audit.json', 
        format: 'json' 
      }
      expect { cli.prod_audit }.not_to raise_error

      # Validate command options
      cli.options = { 
        version: version, 
        check_dependencies: true, 
        security_scan: true, 
        format: 'json' 
      }
      expect { cli.prod_validate }.not_to raise_error

      # Monitor command options
      cli.options = { 
        action: 'start', 
        dashboard: true, 
        port: 3007, 
        alerts: true 
      }
      expect { cli.prod_monitor }.not_to raise_error
    end
  end

  describe 'Real-time Monitoring Integration' do
    before do
      # Start production monitoring for real-time tests
      production_monitor.start_production_monitoring
    end

    after do
      # Clean up monitoring
      production_monitor.stop_production_monitoring if production_monitor.running?
    end

    it 'provides real-time deployment monitoring during deployment' do
      cli.options = { backup: false, validate: false }

      # Should monitor deployment in real-time
      expect(production_monitor).to receive(:monitor_deployment)

      cli.prod_deploy(version)
    end

    it 'detects and reports real-time alerts' do
      cli.options = { action: 'status', alerts: true }

      # Mock active alerts
      allow(production_monitor).to receive(:real_time_alerts).and_return([
        {
          type: 'service_health',
          severity: 'warning',
          message: 'High response time in gateway service',
          timestamp: Time.now.to_i
        }
      ])

      cli.prod_monitor

      expect($stdout).to have_received(:puts).with(/⚠️.*High response time in gateway service/)
    end
  end

  describe 'Security Integration' do
    it 'integrates security validation throughout deployment workflow' do
      cli.options = { validate: true, force: false }

      # Should validate deployment which includes security checks
      expect(production_monitor).to receive(:validate_deployment).with(version)

      cli.prod_deploy(version)
    end

    it 'prevents deployment when security audit fails' do
      cli.options = { validate: true, force: false }

      # Mock security failure in validation
      allow(production_monitor).to receive(:validate_deployment).and_return({ 
        deployment_allowed: false, 
        status: 'validation_failed' 
      })

      # Should not proceed with deployment
      expect(deployment_manager).not_to receive(:deploy_to_production)

      cli.prod_deploy(version)
    end
  end

  describe 'Backup Integration' do
    it 'creates backup before deployment and validates backup system' do
      cli.options = { backup: true }

      aggregate_failures 'backup integration' do
        # Should create deployment backup via CLI method
        expect(cli).to receive(:create_deployment_backup).with(version).and_return({ 
          status: 'success', 
          backup_id: 'backup-123' 
        })

        # Execute deployment that includes backup
        cli.prod_deploy(version)
      end
    end
  end

  describe 'Monitoring Dashboard Integration' do
    it 'integrates monitoring dashboard with production management' do
      cli.options = { action: 'start', dashboard: true, port: 3006 }

      # Set up monitoring to be already running for dashboard test
      allow(production_monitor).to receive(:running?).and_return(true)

      # Mock dashboard service
      dashboard_result = { url: 'http://localhost:3006' }
      expect(monitoring_service).to receive(:start_dashboard).with(port: 3006).and_return(dashboard_result)

      cli.prod_monitor

      expect($stdout).to have_received(:puts).with("✅ Dashboard available at: http://localhost:3006")
    end
  end
end