# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/deployment_manager'

RSpec.describe TcfPlatform::DeploymentManager do
  let(:config_manager) { instance_double(TcfPlatform::ConfigManager) }
  let(:docker_manager) { instance_double(TcfPlatform::DockerManager) }
  let(:security_validator) { instance_double(TcfPlatform::SecurityValidator) }
  let(:monitoring_service) { instance_double(TcfPlatform::Monitoring::MonitoringService) }
  let(:backup_manager) { instance_double(TcfPlatform::BackupManager) }
  let(:deployment_manager) do
    described_class.new(
      config_manager: config_manager,
      docker_manager: docker_manager,
      security_validator: security_validator,
      monitoring_service: monitoring_service,
      backup_manager: backup_manager
    )
  end

  before do
    allow(config_manager).to receive(:load_production_config).and_return({
                                                                           'environment' => 'production',
                                                                           'ssl' => { 'enabled' => true },
                                                                           'secrets' => { 'encrypted' => true }
                                                                         })
    allow(docker_manager).to receive(:service_status).and_return({})
    allow(security_validator).to receive(:validate_production_security).and_return({ valid: true })
    allow(monitoring_service).to receive(:health_check).and_return({ status: 'ok' })
    allow(backup_manager).to receive(:verify_backup_system).and_return({ status: 'ready' })
  end

  describe '#validate_production_readiness' do
    context 'when all production prerequisites are met' do
      it 'validates security configuration is complete' do
        allow(security_validator).to receive(:validate_production_security).and_return({
                                                                                          valid: true,
                                                                                          checks: {
                                                                                            secrets_configured: true,
                                                                                            ssl_certificates: true,
                                                                                            firewall_rules: true,
                                                                                            access_controls: true
                                                                                          }
                                                                                        })

        result = deployment_manager.validate_production_readiness

        aggregate_failures do
          expect(result[:security][:valid]).to be true
          expect(result[:security][:checks][:secrets_configured]).to be true
          expect(result[:security][:checks][:ssl_certificates]).to be true
          expect(result[:security][:checks][:firewall_rules]).to be true
          expect(result[:security][:checks][:access_controls]).to be true
          expect(security_validator).to have_received(:validate_production_security)
        end
      end

      it 'validates infrastructure components are ready' do
        allow(docker_manager).to receive(:verify_swarm_cluster).and_return({
                                                                             status: 'ready',
                                                                             nodes: 3,
                                                                             manager_nodes: 1,
                                                                             worker_nodes: 2
                                                                           })
        allow(deployment_manager).to receive(:check_load_balancer).and_return({ status: 'healthy' })

        result = deployment_manager.validate_production_readiness

        aggregate_failures do
          expect(result[:infrastructure][:docker_swarm][:status]).to eq('ready')
          expect(result[:infrastructure][:docker_swarm][:nodes]).to eq(3)
          expect(result[:infrastructure][:load_balancer][:status]).to eq('healthy')
          expect(result[:infrastructure][:monitoring][:status]).to eq('ok')
          expect(result[:infrastructure][:backup_system][:status]).to eq('ready')
        end
      end

      it 'validates all services are healthy and tests passing' do
        allow(docker_manager).to receive(:service_status).and_return({
                                                                       'tcf-gateway' => { status: 'healthy', replicas: 2 },
                                                                       'tcf-personas' => { status: 'healthy', replicas: 2 },
                                                                       'tcf-workflows' => { status: 'healthy', replicas: 2 },
                                                                       'tcf-projects' => { status: 'healthy', replicas: 2 },
                                                                       'tcf-context' => { status: 'healthy', replicas: 2 },
                                                                       'tcf-tokens' => { status: 'healthy', replicas: 2 }
                                                                     })
        allow(deployment_manager).to receive(:run_security_scans).and_return({ status: 'passed', vulnerabilities: 0 })
        allow(deployment_manager).to receive(:verify_tests_passing).and_return({ status: 'passed', total: 511, failed: 0 })

        result = deployment_manager.validate_production_readiness

        aggregate_failures do
          expect(result[:services][:all_healthy]).to be true
          expect(result[:services][:tests_passing]).to be true
          expect(result[:services][:security_scans][:status]).to eq('passed')
          expect(result[:services][:security_scans][:vulnerabilities]).to eq(0)
          expect(result[:overall_status]).to eq('ready')
        end
      end
    end

    context 'when security prerequisites are not met' do
      it 'fails validation when secrets are not configured' do
        allow(security_validator).to receive(:validate_production_security).and_return({
                                                                                          valid: false,
                                                                                          checks: {
                                                                                            secrets_configured: false,
                                                                                            ssl_certificates: true,
                                                                                            firewall_rules: true,
                                                                                            access_controls: true
                                                                                          },
                                                                                          errors: ['Production secrets not configured']
                                                                                        })

        result = deployment_manager.validate_production_readiness

        aggregate_failures do
          expect(result[:security][:valid]).to be false
          expect(result[:security][:checks][:secrets_configured]).to be false
          expect(result[:security][:errors]).to include('Production secrets not configured')
          expect(result[:overall_status]).to eq('not_ready')
        end
      end

      it 'fails validation when SSL certificates are missing' do
        allow(security_validator).to receive(:validate_production_security).and_return({
                                                                                          valid: false,
                                                                                          checks: {
                                                                                            secrets_configured: true,
                                                                                            ssl_certificates: false,
                                                                                            firewall_rules: true,
                                                                                            access_controls: true
                                                                                          },
                                                                                          errors: ['SSL certificates not deployed']
                                                                                        })

        result = deployment_manager.validate_production_readiness

        aggregate_failures do
          expect(result[:security][:valid]).to be false
          expect(result[:security][:checks][:ssl_certificates]).to be false
          expect(result[:security][:errors]).to include('SSL certificates not deployed')
          expect(result[:overall_status]).to eq('not_ready')
        end
      end

      it 'fails validation when firewall rules are not configured' do
        allow(security_validator).to receive(:validate_production_security).and_return({
                                                                                          valid: false,
                                                                                          checks: {
                                                                                            secrets_configured: true,
                                                                                            ssl_certificates: true,
                                                                                            firewall_rules: false,
                                                                                            access_controls: true
                                                                                          },
                                                                                          errors: ['Firewall rules not configured']
                                                                                        })

        result = deployment_manager.validate_production_readiness

        aggregate_failures do
          expect(result[:security][:valid]).to be false
          expect(result[:security][:checks][:firewall_rules]).to be false
          expect(result[:security][:errors]).to include('Firewall rules not configured')
          expect(result[:overall_status]).to eq('not_ready')
        end
      end
    end

    context 'when infrastructure prerequisites are not met' do
      it 'fails validation when Docker Swarm is not ready' do
        allow(docker_manager).to receive(:verify_swarm_cluster).and_return({
                                                                             status: 'error',
                                                                             error: 'Swarm cluster not initialized'
                                                                           })

        result = deployment_manager.validate_production_readiness

        aggregate_failures do
          expect(result[:infrastructure][:docker_swarm][:status]).to eq('error')
          expect(result[:infrastructure][:docker_swarm][:error]).to eq('Swarm cluster not initialized')
          expect(result[:overall_status]).to eq('not_ready')
        end
      end

      it 'fails validation when monitoring system is down' do
        allow(monitoring_service).to receive(:health_check).and_return({
                                                                         status: 'error',
                                                                         error: 'Prometheus unreachable'
                                                                       })

        result = deployment_manager.validate_production_readiness

        aggregate_failures do
          expect(result[:infrastructure][:monitoring][:status]).to eq('error')
          expect(result[:infrastructure][:monitoring][:error]).to eq('Prometheus unreachable')
          expect(result[:overall_status]).to eq('not_ready')
        end
      end

      it 'fails validation when backup system is not ready' do
        allow(backup_manager).to receive(:verify_backup_system).and_return({
                                                                             status: 'error',
                                                                             error: 'S3 backup bucket not accessible'
                                                                           })

        result = deployment_manager.validate_production_readiness

        aggregate_failures do
          expect(result[:infrastructure][:backup_system][:status]).to eq('error')
          expect(result[:infrastructure][:backup_system][:error]).to eq('S3 backup bucket not accessible')
          expect(result[:overall_status]).to eq('not_ready')
        end
      end
    end

    context 'when service prerequisites are not met' do
      it 'fails validation when services are unhealthy' do
        allow(docker_manager).to receive(:service_status).and_return({
                                                                       'tcf-gateway' => { status: 'unhealthy', error: 'Connection timeout' },
                                                                       'tcf-personas' => { status: 'healthy', replicas: 2 }
                                                                     })

        result = deployment_manager.validate_production_readiness

        aggregate_failures do
          expect(result[:services][:all_healthy]).to be false
          expect(result[:services][:unhealthy_services]).to include('tcf-gateway')
          expect(result[:overall_status]).to eq('not_ready')
        end
      end

      it 'fails validation when security scans find vulnerabilities' do
        allow(deployment_manager).to receive(:run_security_scans).and_return({
                                                                               status: 'failed',
                                                                               vulnerabilities: 3,
                                                                               high_severity: 1,
                                                                               details: ['Critical XSS vulnerability in gateway']
                                                                             })

        result = deployment_manager.validate_production_readiness

        aggregate_failures do
          expect(result[:services][:security_scans][:status]).to eq('failed')
          expect(result[:services][:security_scans][:vulnerabilities]).to eq(3)
          expect(result[:services][:security_scans][:high_severity]).to eq(1)
          expect(result[:overall_status]).to eq('not_ready')
        end
      end

      it 'fails validation when tests are failing' do
        allow(deployment_manager).to receive(:verify_tests_passing).and_return({
                                                                                 status: 'failed',
                                                                                 total: 511,
                                                                                 failed: 5,
                                                                                 failures: ['Authentication spec failed', 'Security validation failed']
                                                                               })

        result = deployment_manager.validate_production_readiness

        aggregate_failures do
          expect(result[:services][:tests_passing]).to be false
          expect(result[:services][:test_results][:failed]).to eq(5)
          expect(result[:services][:test_results][:failures]).to include('Authentication spec failed')
          expect(result[:overall_status]).to eq('not_ready')
        end
      end
    end
  end

  describe '#prepare_production_environment' do
    let(:production_config) do
      {
        'ssl_certificates' => { 'path' => '/etc/ssl/certs', 'key_path' => '/etc/ssl/private' },
        'secrets' => { 'encryption_key' => 'prod_key_12345' },
        'firewall' => { 'allowed_ports' => [443, 80, 22], 'blocked_ips' => [] },
        'monitoring' => { 'enabled' => true, 'prometheus_url' => 'https://prometheus.prod.local' }
      }
    end

    context 'when preparation succeeds' do
      it 'applies security hardening configuration' do
        allow(security_validator).to receive(:apply_security_hardening).and_return({
                                                                                     status: 'success',
                                                                                     applied: ['disable_debug_mode', 'enable_csrf_protection', 'secure_headers']
                                                                                   })

        result = deployment_manager.prepare_production_environment(production_config)

        aggregate_failures do
          expect(result[:security_hardening][:status]).to eq('success')
          expect(result[:security_hardening][:applied]).to include('disable_debug_mode')
          expect(result[:security_hardening][:applied]).to include('enable_csrf_protection')
          expect(result[:security_hardening][:applied]).to include('secure_headers')
          expect(security_validator).to have_received(:apply_security_hardening)
        end
      end

      it 'deploys SSL certificates successfully' do
        allow(deployment_manager).to receive(:deploy_ssl_certificates).and_return({
                                                                                    status: 'success',
                                                                                    certificates: ['wildcard.tcf.local', 'api.tcf.local']
                                                                                  })

        result = deployment_manager.prepare_production_environment(production_config)

        aggregate_failures do
          expect(result[:ssl_deployment][:status]).to eq('success')
          expect(result[:ssl_deployment][:certificates]).to include('wildcard.tcf.local')
          expect(result[:ssl_deployment][:certificates]).to include('api.tcf.local')
        end
      end

      it 'encrypts and deploys secrets securely' do
        allow(deployment_manager).to receive(:deploy_encrypted_secrets).and_return({
                                                                                     status: 'success',
                                                                                     secrets_deployed: 15,
                                                                                     encryption_method: 'AES-256-GCM'
                                                                                   })

        result = deployment_manager.prepare_production_environment(production_config)

        aggregate_failures do
          expect(result[:secrets_deployment][:status]).to eq('success')
          expect(result[:secrets_deployment][:secrets_deployed]).to eq(15)
          expect(result[:secrets_deployment][:encryption_method]).to eq('AES-256-GCM')
        end
      end

      it 'configures firewall rules correctly' do
        allow(deployment_manager).to receive(:configure_firewall).and_return({
                                                                               status: 'success',
                                                                               rules_applied: 12,
                                                                               allowed_ports: [443, 80, 22],
                                                                               blocked_ranges: ['10.0.0.0/8']
                                                                             })

        result = deployment_manager.prepare_production_environment(production_config)

        aggregate_failures do
          expect(result[:firewall_configuration][:status]).to eq('success')
          expect(result[:firewall_configuration][:rules_applied]).to eq(12)
          expect(result[:firewall_configuration][:allowed_ports]).to include(443, 80, 22)
        end
      end

      it 'enables monitoring and alerting systems' do
        allow(monitoring_service).to receive(:enable_production_monitoring).and_return({
                                                                                         status: 'success',
                                                                                         dashboards_enabled: 5,
                                                                                         alerts_configured: 15
                                                                                       })

        result = deployment_manager.prepare_production_environment(production_config)

        aggregate_failures do
          expect(result[:monitoring_enablement][:status]).to eq('success')
          expect(result[:monitoring_enablement][:dashboards_enabled]).to eq(5)
          expect(result[:monitoring_enablement][:alerts_configured]).to eq(15)
          expect(monitoring_service).to have_received(:enable_production_monitoring)
        end
      end
    end

    context 'when preparation encounters errors' do
      it 'handles SSL certificate deployment failure' do
        allow(deployment_manager).to receive(:deploy_ssl_certificates).and_return({
                                                                                    status: 'error',
                                                                                    error: 'Certificate authority unreachable'
                                                                                  })

        result = deployment_manager.prepare_production_environment(production_config)

        aggregate_failures do
          expect(result[:ssl_deployment][:status]).to eq('error')
          expect(result[:ssl_deployment][:error]).to eq('Certificate authority unreachable')
          expect(result[:overall_status]).to eq('partial_failure')
        end
      end

      it 'handles secrets encryption failure' do
        allow(deployment_manager).to receive(:deploy_encrypted_secrets).and_return({
                                                                                     status: 'error',
                                                                                     error: 'Encryption key invalid'
                                                                                   })

        result = deployment_manager.prepare_production_environment(production_config)

        aggregate_failures do
          expect(result[:secrets_deployment][:status]).to eq('error')
          expect(result[:secrets_deployment][:error]).to eq('Encryption key invalid')
          expect(result[:overall_status]).to eq('partial_failure')
        end
      end

      it 'handles firewall configuration failure' do
        allow(deployment_manager).to receive(:configure_firewall).and_return({
                                                                               status: 'error',
                                                                               error: 'Insufficient privileges to modify firewall rules'
                                                                             })

        result = deployment_manager.prepare_production_environment(production_config)

        aggregate_failures do
          expect(result[:firewall_configuration][:status]).to eq('error')
          expect(result[:firewall_configuration][:error]).to eq('Insufficient privileges to modify firewall rules')
          expect(result[:overall_status]).to eq('partial_failure')
        end
      end

      it 'handles monitoring system enablement failure' do
        allow(monitoring_service).to receive(:enable_production_monitoring).and_return({
                                                                                         status: 'error',
                                                                                         error: 'Prometheus configuration invalid'
                                                                                       })

        result = deployment_manager.prepare_production_environment(production_config)

        aggregate_failures do
          expect(result[:monitoring_enablement][:status]).to eq('error')
          expect(result[:monitoring_enablement][:error]).to eq('Prometheus configuration invalid')
          expect(result[:overall_status]).to eq('partial_failure')
        end
      end
    end

    context 'when critical preparation steps fail' do
      it 'aborts deployment when security hardening fails' do
        allow(security_validator).to receive(:apply_security_hardening).and_return({
                                                                                     status: 'critical_error',
                                                                                     error: 'Cannot disable debug mode - production deployment unsafe'
                                                                                   })

        expect do
          deployment_manager.prepare_production_environment(production_config)
        end.to raise_error(TcfPlatform::ProductionDeploymentError, /Cannot disable debug mode/)
      end
    end
  end

  describe '#deploy_to_production' do
    let(:deployment_config) do
      {
        'replicas' => { 'gateway' => 3, 'personas' => 2, 'workflows' => 2 },
        'rollback_strategy' => 'blue_green',
        'health_check_timeout' => 300
      }
    end

    context 'when deployment succeeds' do
      it 'orchestrates full production deployment with validation' do
        allow(deployment_manager).to receive(:validate_production_readiness).and_return({
                                                                                           overall_status: 'ready'
                                                                                         })
        allow(deployment_manager).to receive(:execute_blue_green_deployment).and_return({
                                                                                           status: 'success',
                                                                                           services_deployed: 6,
                                                                                           rollback_ready: true
                                                                                         })
        allow(deployment_manager).to receive(:verify_deployment_health).and_return({
                                                                                      status: 'healthy',
                                                                                      all_services_responding: true
                                                                                    })

        result = deployment_manager.deploy_to_production(deployment_config)

        aggregate_failures do
          expect(result[:pre_deployment_validation][:overall_status]).to eq('ready')
          expect(result[:deployment][:status]).to eq('success')
          expect(result[:deployment][:services_deployed]).to eq(6)
          expect(result[:post_deployment_health][:status]).to eq('healthy')
          expect(result[:overall_status]).to eq('success')
        end
      end
    end

    context 'when deployment validation fails' do
      it 'prevents deployment when readiness check fails' do
        allow(deployment_manager).to receive(:validate_production_readiness).and_return({
                                                                                           overall_status: 'not_ready',
                                                                                           errors: ['SSL certificates missing']
                                                                                         })

        expect do
          deployment_manager.deploy_to_production(deployment_config)
        end.to raise_error(TcfPlatform::ProductionValidationError, /SSL certificates missing/)
      end
    end
  end

  describe 'integration with SecurityValidator' do
    it 'delegates security validation to SecurityValidator' do
      deployment_manager.validate_production_readiness

      expect(security_validator).to have_received(:validate_production_security)
    end

    it 'delegates security hardening to SecurityValidator' do
      production_config = { 'environment' => 'production' }
      allow(security_validator).to receive(:apply_security_hardening).and_return({ status: 'success' })
      allow(deployment_manager).to receive(:deploy_ssl_certificates).and_return({ status: 'success' })
      allow(deployment_manager).to receive(:deploy_encrypted_secrets).and_return({ status: 'success' })
      allow(deployment_manager).to receive(:configure_firewall).and_return({ status: 'success' })
      allow(monitoring_service).to receive(:enable_production_monitoring).and_return({ status: 'success' })

      deployment_manager.prepare_production_environment(production_config)

      expect(security_validator).to have_received(:apply_security_hardening)
    end
  end
end