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
  
  # Real dependencies for integration testing
  let(:config_manager) { TcfPlatform::ConfigManager.new }
  let(:docker_manager) { TcfPlatform::DockerManager.new }
  let(:monitoring_service) { TcfPlatform::Monitoring::MonitoringService.new }
  let(:security_validator) do
    TcfPlatform::SecurityValidator.new(
      config_manager: config_manager,
      docker_manager: docker_manager
    )
  end
  let(:backup_manager) do
    TcfPlatform::BackupManager.new(
      config_manager, 
      docker_manager
    )
  end
  let(:deployment_manager) do
    TcfPlatform::DeploymentManager.new(
      config_manager: config_manager,
      docker_manager: docker_manager,
      security_validator: security_validator,
      monitoring_service: monitoring_service,
      backup_manager: backup_manager
    )
  end
  let(:production_monitor) do
    TcfPlatform::Monitoring::ProductionMonitor.new(
      monitoring_service: monitoring_service,
      deployment_manager: deployment_manager,
      security_validator: security_validator,
      backup_manager: backup_manager
    )
  end

  before do
    # Suppress CLI output during integration tests
    allow($stdout).to receive(:puts)
    allow($stdout).to receive(:print)
    allow($stdin).to receive(:gets).and_return("y\n")

    # Mock external dependencies for integration testing
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

    # Mock backup system
    allow(backup_manager).to receive(:verify_backup_system).and_return({ status: 'healthy' })
    allow(backup_manager).to receive(:create_backup).and_return({ 
      status: 'success', 
      backup_id: 'backup-123' 
    })

    # Mock monitoring services
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

    # Override CLI dependency creation to use real objects
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
        expect(production_monitor).to receive(:start_production_monitoring).and_call_original

        # Backup should be created
        expect(backup_manager).to receive(:create_backup).and_call_original

        # Validation should pass
        expect(production_monitor).to receive(:validate_deployment).and_call_original

        # Deployment should execute
        expect(deployment_manager).to receive(:deploy_to_production).and_call_original

        # Post-deployment monitoring should occur
        expect(production_monitor).to receive(:monitor_deployment).and_call_original

        # Execute the deployment
        cli.prod_deploy(version)

        # Verify production monitor is running after deployment
        expect(production_monitor.running?).to be true
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
      # Mock blue-green deployer creation
      load_balancer_mock = Object.new
      allow(load_balancer_mock).to receive(:switch_traffic)
      allow(load_balancer_mock).to receive(:get_current_target).and_return('service-blue')
      
      deployment_validator = TcfPlatform::DeploymentValidator.new
      blue_green_deployer = TcfPlatform::BlueGreenDeployer.new(
        docker_manager: docker_manager,
        monitoring_service: monitoring_service,
        deployment_validator: deployment_validator,
        load_balancer: load_balancer_mock
      )
      
      allow(cli).to receive(:create_blue_green_deployer).and_return(blue_green_deployer)
      allow(blue_green_deployer).to receive(:rollback).and_return(rollback_result)
    end

    it 'executes end-to-end production rollback successfully' do
      cli.options = { to_version: 'v2.0.0', reason: 'Critical bug', force: true }

      aggregate_failures 'production rollback workflow' do
        # Should rollback all services
        services = %w[gateway personas workflows projects context tokens]
        services.each do |service|
          expect_any_instance_of(TcfPlatform::BlueGreenDeployer)
            .to receive(:rollback).with(
              service,
              reason: 'Critical bug',
              version: 'v2.0.0',
              manual: true
            ).and_return(rollback_result)
        end

        # Should check post-rollback health
        expect(production_monitor).to receive(:deployment_health_status).and_call_original

        # Execute rollback
        cli.prod_rollback

        # Should display success message
        expect($stdout).to have_received(:puts).with("✅ Production rollback successful!")
      end
    end

    it 'handles rollback confirmation workflow' do
      cli.options = { force: false }
      
      # Mock user confirmation
      expect($stdin).to receive(:gets).and_return("y\n")
      expect($stdout).to receive(:print).with("Are you sure you want to continue? (y/N): ")

      cli.prod_rollback
    end
  end

  describe 'Production Monitoring Workflow' do
    it 'manages complete monitoring lifecycle' do
      aggregate_failures 'monitoring lifecycle' do
        # Start monitoring
        cli.options = { action: 'start' }
        cli.prod_monitor
        expect(production_monitor.running?).to be true

        # Check status
        cli.options = { action: 'status' }
        expect { cli.prod_monitor }.not_to raise_error

        # Stop monitoring
        cli.options = { action: 'stop' }
        cli.prod_monitor
        expect(production_monitor.running?).to be false
      end
    end

    it 'handles dashboard management' do
      cli.options = { action: 'start', dashboard: true, port: 3006 }

      # Mock dashboard start
      dashboard_result = { url: 'http://localhost:3006' }
      allow(monitoring_service).to receive(:start_dashboard).with(port: 3006).and_return(dashboard_result)

      cli.prod_monitor

      expect(monitoring_service).to have_received(:start_dashboard).with(port: 3006)
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
      allow(deployment_manager).to receive(:validate_production_readiness)
        .and_return({ overall_status: 'not_ready' })

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
      output = capture_stdout { cli.help }

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
      deployment_id = "deploy-#{version}-#{Time.now.to_i}"

      # Should monitor deployment in real-time
      expect(production_monitor).to receive(:monitor_deployment).with(anything).and_call_original

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

      # Security validation should be called multiple times throughout workflow
      expect(security_validator).to receive(:validate_production_security).at_least(:twice).and_call_original

      cli.prod_deploy(version)
    end

    it 'prevents deployment when security audit fails' do
      cli.options = { validate: true, force: false }

      # Mock security failure
      allow(security_validator).to receive(:validate_production_security)
        .and_return({ valid: false, errors: ['SSL certificates expired'] })

      # Should not proceed with deployment
      expect(deployment_manager).not_to receive(:deploy_to_production)

      cli.prod_deploy(version)
    end
  end

  describe 'Backup Integration' do
    it 'creates backup before deployment and validates backup system' do
      cli.options = { backup: true }

      aggregate_failures 'backup integration' do
        # Should create deployment backup
        expect(backup_manager).to receive(:create_backup).and_call_original

        # Should verify backup system in health checks
        expect(backup_manager).to receive(:verify_backup_system).and_call_original

        cli.prod_deploy(version)
      end
    end
  end

  describe 'Monitoring Dashboard Integration' do
    it 'integrates monitoring dashboard with production management' do
      cli.options = { action: 'start', dashboard: true, port: 3006 }

      # Mock dashboard service
      dashboard_result = { url: 'http://localhost:3006' }
      expect(monitoring_service).to receive(:start_dashboard).with(port: 3006).and_return(dashboard_result)

      cli.prod_monitor

      expect($stdout).to have_received(:puts).with("✅ Dashboard available at: http://localhost:3006")
    end
  end
end