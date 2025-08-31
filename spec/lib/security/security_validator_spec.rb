# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/security/security_validator'

RSpec.describe TcfPlatform::SecurityValidator do
  let(:config_manager) { instance_double(TcfPlatform::ConfigManager) }
  let(:docker_manager) { instance_double(TcfPlatform::DockerManager) }
  let(:security_validator) { described_class.new(config_manager, docker_manager) }

  before do
    allow(config_manager).to receive(:load_security_config).and_return({
                                                                         'secrets' => { 'encryption_key' => 'test_key_123' },
                                                                         'ssl' => { 'enabled' => true, 'cert_path' => '/etc/ssl' },
                                                                         'firewall' => { 'enabled' => true },
                                                                         'access_control' => { 'enabled' => true }
                                                                       })
    allow(docker_manager).to receive(:container_security_context).and_return({
                                                                               'non_root_user' => true,
                                                                               'read_only_filesystem' => true
                                                                             })
  end

  describe '#validate_production_security' do
    context 'when all security checks pass' do
      it 'validates secrets are properly configured and encrypted' do
        allow(security_validator).to receive(:check_secrets_configuration).and_return({
                                                                                        configured: true,
                                                                                        encrypted: true,
                                                                                        rotation_enabled: true,
                                                                                        count: 15
                                                                                      })

        result = security_validator.validate_production_security

        aggregate_failures do
          expect(result[:valid]).to be true
          expect(result[:checks][:secrets_configured]).to be true
          expect(result[:secrets_details][:encrypted]).to be true
          expect(result[:secrets_details][:rotation_enabled]).to be true
          expect(result[:secrets_details][:count]).to eq(15)
        end
      end

      it 'validates SSL certificates are properly deployed' do
        allow(security_validator).to receive(:check_ssl_certificates).and_return({
                                                                                   deployed: true,
                                                                                   valid: true,
                                                                                   expiry_days: 85,
                                                                                   certificates: ['wildcard.tcf.local', 'api.tcf.local']
                                                                                 })

        result = security_validator.validate_production_security

        aggregate_failures do
          expect(result[:checks][:ssl_certificates]).to be true
          expect(result[:ssl_details][:deployed]).to be true
          expect(result[:ssl_details][:valid]).to be true
          expect(result[:ssl_details][:expiry_days]).to eq(85)
          expect(result[:ssl_details][:certificates]).to include('wildcard.tcf.local')
        end
      end

      it 'validates firewall rules are properly configured' do
        allow(security_validator).to receive(:check_firewall_rules).and_return({
                                                                                 configured: true,
                                                                                 rules_count: 25,
                                                                                 allowed_ports: [443, 80, 22],
                                                                                 blocked_ips: ['192.168.1.100'],
                                                                                 default_deny: true
                                                                               })

        result = security_validator.validate_production_security

        aggregate_failures do
          expect(result[:checks][:firewall_rules]).to be true
          expect(result[:firewall_details][:configured]).to be true
          expect(result[:firewall_details][:rules_count]).to eq(25)
          expect(result[:firewall_details][:allowed_ports]).to include(443, 80, 22)
          expect(result[:firewall_details][:default_deny]).to be true
        end
      end

      it 'validates access controls are properly implemented' do
        allow(security_validator).to receive(:check_access_controls).and_return({
                                                                                  rbac_enabled: true,
                                                                                  mfa_required: true,
                                                                                  session_timeout: 3600,
                                                                                  password_policy: {
                                                                                    min_length: 12,
                                                                                    complexity_required: true,
                                                                                    rotation_days: 90
                                                                                  }
                                                                                })

        result = security_validator.validate_production_security

        aggregate_failures do
          expect(result[:checks][:access_controls]).to be true
          expect(result[:access_control_details][:rbac_enabled]).to be true
          expect(result[:access_control_details][:mfa_required]).to be true
          expect(result[:access_control_details][:session_timeout]).to eq(3600)
          expect(result[:access_control_details][:password_policy][:min_length]).to eq(12)
        end
      end

      it 'validates container security configurations' do
        allow(security_validator).to receive(:check_container_security).and_return({
                                                                                     non_root_containers: true,
                                                                                     read_only_filesystems: true,
                                                                                     security_contexts: true,
                                                                                     network_policies: true,
                                                                                     image_scanning: true
                                                                                   })

        result = security_validator.validate_production_security

        aggregate_failures do
          expect(result[:container_security][:non_root_containers]).to be true
          expect(result[:container_security][:read_only_filesystems]).to be true
          expect(result[:container_security][:security_contexts]).to be true
          expect(result[:container_security][:network_policies]).to be true
          expect(result[:container_security][:image_scanning]).to be true
        end
      end

      it 'validates network security configurations' do
        allow(security_validator).to receive(:check_network_security).and_return({
                                                                                   tls_enabled: true,
                                                                                   network_segmentation: true,
                                                                                   intrusion_detection: true,
                                                                                   traffic_encryption: true,
                                                                                   ddos_protection: true
                                                                                 })

        result = security_validator.validate_production_security

        aggregate_failures do
          expect(result[:network_security][:tls_enabled]).to be true
          expect(result[:network_security][:network_segmentation]).to be true
          expect(result[:network_security][:intrusion_detection]).to be true
          expect(result[:network_security][:traffic_encryption]).to be true
          expect(result[:network_security][:ddos_protection]).to be true
        end
      end
    end

    context 'when security checks fail' do
      it 'reports failure when secrets are not configured' do
        allow(security_validator).to receive(:check_secrets_configuration).and_return({
                                                                                        configured: false,
                                                                                        error: 'No secrets found in secure vault'
                                                                                      })

        result = security_validator.validate_production_security

        aggregate_failures do
          expect(result[:valid]).to be false
          expect(result[:checks][:secrets_configured]).to be false
          expect(result[:errors]).to include('No secrets found in secure vault')
        end
      end

      it 'reports failure when SSL certificates are missing or expired' do
        allow(security_validator).to receive(:check_ssl_certificates).and_return({
                                                                                   deployed: false,
                                                                                   error: 'SSL certificate expired 5 days ago'
                                                                                 })

        result = security_validator.validate_production_security

        aggregate_failures do
          expect(result[:checks][:ssl_certificates]).to be false
          expect(result[:errors]).to include('SSL certificate expired 5 days ago')
        end
      end

      it 'reports failure when firewall is not configured' do
        allow(security_validator).to receive(:check_firewall_rules).and_return({
                                                                                 configured: false,
                                                                                 error: 'Firewall service not running'
                                                                               })

        result = security_validator.validate_production_security

        aggregate_failures do
          expect(result[:checks][:firewall_rules]).to be false
          expect(result[:errors]).to include('Firewall service not running')
        end
      end

      it 'reports failure when access controls are insufficient' do
        allow(security_validator).to receive(:check_access_controls).and_return({
                                                                                  rbac_enabled: false,
                                                                                  mfa_required: false,
                                                                                  error: 'Multi-factor authentication not configured'
                                                                                })

        result = security_validator.validate_production_security

        aggregate_failures do
          expect(result[:checks][:access_controls]).to be false
          expect(result[:errors]).to include('Multi-factor authentication not configured')
        end
      end

      it 'reports vulnerability scan findings' do
        allow(security_validator).to receive(:run_vulnerability_scan).and_return({
                                                                                   status: 'completed',
                                                                                   vulnerabilities_found: 3,
                                                                                   high_severity: 1,
                                                                                   medium_severity: 2,
                                                                                   findings: [
                                                                                     { severity: 'HIGH', description: 'SQL injection vulnerability in user search' },
                                                                                     { severity: 'MEDIUM', description: 'Weak password policy' }
                                                                                   ]
                                                                                 })

        result = security_validator.validate_production_security

        aggregate_failures do
          expect(result[:vulnerability_scan][:vulnerabilities_found]).to eq(3)
          expect(result[:vulnerability_scan][:high_severity]).to eq(1)
          expect(result[:vulnerability_scan][:findings]).to include(
            hash_including(severity: 'HIGH', description: 'SQL injection vulnerability in user search')
          )
        end
      end
    end

    context 'when critical security issues are found' do
      it 'marks validation as critical failure for high-severity vulnerabilities' do
        allow(security_validator).to receive(:run_vulnerability_scan).and_return({
                                                                                   status: 'completed',
                                                                                   vulnerabilities_found: 5,
                                                                                   critical_severity: 2,
                                                                                   high_severity: 3,
                                                                                   findings: [
                                                                                     { severity: 'CRITICAL', description: 'Remote code execution vulnerability' },
                                                                                     { severity: 'CRITICAL', description: 'Privilege escalation vulnerability' }
                                                                                   ]
                                                                                 })

        result = security_validator.validate_production_security

        aggregate_failures do
          expect(result[:valid]).to be false
          expect(result[:severity]).to eq('critical')
          expect(result[:vulnerability_scan][:critical_severity]).to eq(2)
          expect(result[:errors]).to include('Critical security vulnerabilities found - deployment blocked')
        end
      end
    end
  end

  describe '#apply_security_hardening' do
    context 'when hardening succeeds' do
      it 'disables debug mode for production' do
        allow(security_validator).to receive(:disable_debug_mode).and_return({ status: 'success' })

        result = security_validator.apply_security_hardening

        aggregate_failures do
          expect(result[:status]).to eq('success')
          expect(result[:applied]).to include('disable_debug_mode')
          expect(security_validator).to have_received(:disable_debug_mode)
        end
      end

      it 'enables CSRF protection' do
        allow(security_validator).to receive(:enable_csrf_protection).and_return({ status: 'success' })

        result = security_validator.apply_security_hardening

        aggregate_failures do
          expect(result[:applied]).to include('enable_csrf_protection')
          expect(security_validator).to have_received(:enable_csrf_protection)
        end
      end

      it 'configures secure headers' do
        allow(security_validator).to receive(:configure_secure_headers).and_return({
                                                                                     status: 'success',
                                                                                     headers: [
                                                                                       'X-Content-Type-Options',
                                                                                       'X-Frame-Options',
                                                                                       'X-XSS-Protection',
                                                                                       'Strict-Transport-Security'
                                                                                     ]
                                                                                   })

        result = security_validator.apply_security_hardening

        aggregate_failures do
          expect(result[:applied]).to include('secure_headers')
          expect(result[:secure_headers][:headers]).to include('X-Content-Type-Options')
          expect(result[:secure_headers][:headers]).to include('Strict-Transport-Security')
        end
      end

      it 'enables rate limiting' do
        allow(security_validator).to receive(:enable_rate_limiting).and_return({
                                                                                 status: 'success',
                                                                                 limits: { api: '1000/hour', auth: '10/minute' }
                                                                               })

        result = security_validator.apply_security_hardening

        aggregate_failures do
          expect(result[:applied]).to include('rate_limiting')
          expect(result[:rate_limiting][:limits][:api]).to eq('1000/hour')
          expect(result[:rate_limiting][:limits][:auth]).to eq('10/minute')
        end
      end

      it 'configures input validation' do
        allow(security_validator).to receive(:configure_input_validation).and_return({
                                                                                       status: 'success',
                                                                                       validators: ['sql_injection', 'xss', 'path_traversal']
                                                                                     })

        result = security_validator.apply_security_hardening

        aggregate_failures do
          expect(result[:applied]).to include('input_validation')
          expect(result[:input_validation][:validators]).to include('sql_injection', 'xss', 'path_traversal')
        end
      end

      it 'removes unnecessary services and ports' do
        allow(security_validator).to receive(:remove_unnecessary_services).and_return({
                                                                                        status: 'success',
                                                                                        removed_services: ['telnet', 'ftp'],
                                                                                        closed_ports: [23, 21, 135]
                                                                                      })

        result = security_validator.apply_security_hardening

        aggregate_failures do
          expect(result[:applied]).to include('remove_unnecessary_services')
          expect(result[:service_hardening][:removed_services]).to include('telnet', 'ftp')
          expect(result[:service_hardening][:closed_ports]).to include(23, 21, 135)
        end
      end
    end

    context 'when hardening encounters errors' do
      it 'handles debug mode disable failure' do
        allow(security_validator).to receive(:disable_debug_mode).and_return({
                                                                               status: 'error',
                                                                               error: 'Cannot modify application configuration'
                                                                             })

        result = security_validator.apply_security_hardening

        aggregate_failures do
          expect(result[:status]).to eq('partial_success')
          expect(result[:errors]).to include('Cannot modify application configuration')
          expect(result[:failed]).to include('disable_debug_mode')
        end
      end

      it 'handles CSRF protection enablement failure' do
        allow(security_validator).to receive(:enable_csrf_protection).and_return({
                                                                                   status: 'error',
                                                                                   error: 'CSRF token generation failed'
                                                                                 })

        result = security_validator.apply_security_hardening

        aggregate_failures do
          expect(result[:errors]).to include('CSRF token generation failed')
          expect(result[:failed]).to include('enable_csrf_protection')
        end
      end

      it 'handles critical hardening failures' do
        allow(security_validator).to receive(:disable_debug_mode).and_return({
                                                                               status: 'critical_error',
                                                                               error: 'Debug mode cannot be disabled - production deployment unsafe'
                                                                             })

        expect do
          security_validator.apply_security_hardening
        end.to raise_error(TcfPlatform::SecurityHardeningError, /Debug mode cannot be disabled/)
      end
    end
  end

  describe '#run_compliance_check' do
    context 'when compliance checks pass' do
      it 'validates OWASP Top 10 compliance' do
        allow(security_validator).to receive(:check_owasp_top_10_compliance).and_return({
                                                                                          compliant: true,
                                                                                          checks: {
                                                                                            injection: 'PASS',
                                                                                            broken_authentication: 'PASS',
                                                                                            sensitive_data_exposure: 'PASS',
                                                                                            xml_external_entities: 'PASS',
                                                                                            broken_access_control: 'PASS',
                                                                                            security_misconfiguration: 'PASS',
                                                                                            cross_site_scripting: 'PASS',
                                                                                            insecure_deserialization: 'PASS',
                                                                                            known_vulnerabilities: 'PASS',
                                                                                            insufficient_logging: 'PASS'
                                                                                          }
                                                                                        })

        result = security_validator.run_compliance_check

        aggregate_failures do
          expect(result[:owasp_top_10][:compliant]).to be true
          expect(result[:owasp_top_10][:checks][:injection]).to eq('PASS')
          expect(result[:owasp_top_10][:checks][:broken_authentication]).to eq('PASS')
          expect(result[:owasp_top_10][:checks][:cross_site_scripting]).to eq('PASS')
        end
      end

      it 'validates SOC 2 compliance requirements' do
        allow(security_validator).to receive(:check_soc2_compliance).and_return({
                                                                                  compliant: true,
                                                                                  controls: {
                                                                                    security: 'IMPLEMENTED',
                                                                                    availability: 'IMPLEMENTED',
                                                                                    processing_integrity: 'IMPLEMENTED',
                                                                                    confidentiality: 'IMPLEMENTED',
                                                                                    privacy: 'IMPLEMENTED'
                                                                                  }
                                                                                })

        result = security_validator.run_compliance_check

        aggregate_failures do
          expect(result[:soc2][:compliant]).to be true
          expect(result[:soc2][:controls][:security]).to eq('IMPLEMENTED')
          expect(result[:soc2][:controls][:confidentiality]).to eq('IMPLEMENTED')
        end
      end

      it 'validates data protection compliance (GDPR/CCPA)' do
        allow(security_validator).to receive(:check_data_protection_compliance).and_return({
                                                                                             compliant: true,
                                                                                             requirements: {
                                                                                               data_encryption: 'COMPLIANT',
                                                                                               consent_management: 'COMPLIANT',
                                                                                               data_retention: 'COMPLIANT',
                                                                                               right_to_deletion: 'COMPLIANT',
                                                                                               breach_notification: 'COMPLIANT'
                                                                                             }
                                                                                           })

        result = security_validator.run_compliance_check

        aggregate_failures do
          expect(result[:data_protection][:compliant]).to be true
          expect(result[:data_protection][:requirements][:data_encryption]).to eq('COMPLIANT')
          expect(result[:data_protection][:requirements][:consent_management]).to eq('COMPLIANT')
        end
      end
    end

    context 'when compliance checks fail' do
      it 'reports OWASP Top 10 violations' do
        allow(security_validator).to receive(:check_owasp_top_10_compliance).and_return({
                                                                                          compliant: false,
                                                                                          checks: {
                                                                                            injection: 'FAIL',
                                                                                            cross_site_scripting: 'FAIL'
                                                                                          },
                                                                                          violations: [
                                                                                            'SQL injection vulnerability in user search',
                                                                                            'XSS vulnerability in comment system'
                                                                                          ]
                                                                                        })

        result = security_validator.run_compliance_check

        aggregate_failures do
          expect(result[:owasp_top_10][:compliant]).to be false
          expect(result[:owasp_top_10][:checks][:injection]).to eq('FAIL')
          expect(result[:owasp_top_10][:violations]).to include('SQL injection vulnerability in user search')
        end
      end

      it 'reports data protection compliance failures' do
        allow(security_validator).to receive(:check_data_protection_compliance).and_return({
                                                                                             compliant: false,
                                                                                             requirements: {
                                                                                               data_encryption: 'NON_COMPLIANT',
                                                                                               consent_management: 'NON_COMPLIANT'
                                                                                             },
                                                                                             violations: [
                                                                                               'Personal data stored without encryption',
                                                                                               'Consent withdrawal mechanism not implemented'
                                                                                             ]
                                                                                           })

        result = security_validator.run_compliance_check

        aggregate_failures do
          expect(result[:data_protection][:compliant]).to be false
          expect(result[:data_protection][:violations]).to include('Personal data stored without encryption')
          expect(result[:data_protection][:violations]).to include('Consent withdrawal mechanism not implemented')
        end
      end
    end
  end

  describe 'error handling and edge cases' do
    it 'handles configuration loading failures gracefully' do
      allow(config_manager).to receive(:load_security_config).and_raise(StandardError, 'Configuration file not found')

      expect do
        security_validator.validate_production_security
      end.to raise_error(TcfPlatform::SecurityConfigurationError, /Configuration file not found/)
    end

    it 'handles network connectivity issues during security checks' do
      allow(security_validator).to receive(:check_ssl_certificates).and_raise(Net::TimeoutError, 'Certificate authority timeout')

      result = security_validator.validate_production_security

      aggregate_failures do
        expect(result[:valid]).to be false
        expect(result[:errors]).to include('Certificate validation failed: Certificate authority timeout')
      end
    end

    it 'handles insufficient privileges for security hardening' do
      allow(security_validator).to receive(:configure_firewall).and_raise(Errno::EACCES, 'Permission denied')

      expect do
        security_validator.apply_security_hardening
      end.to raise_error(TcfPlatform::InsufficientPrivilegesError, /Permission denied/)
    end
  end
end