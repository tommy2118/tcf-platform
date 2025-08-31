# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/deployment_validator'

RSpec.describe TcfPlatform::DeploymentValidator do
  let(:docker_manager) { instance_double('TcfPlatform::DockerManager') }
  let(:monitoring_service) { instance_double('TcfPlatform::MonitoringService') }
  let(:security_validator) { instance_double('TcfPlatform::SecurityValidator') }
  let(:resource_manager) { instance_double('TcfPlatform::ResourceManager') }

  let(:validator) do
    described_class.new(
      docker_manager: docker_manager,
      monitoring_service: monitoring_service,
      security_validator: security_validator,
      resource_manager: resource_manager
    )
  end

  let(:valid_deployment_config) do
    {
      image: 'tcf/gateway:v1.2.0',
      service: 'gateway',
      replicas: 2,
      resources: {
        cpu: '500m',
        memory: '1Gi'
      },
      health_check: {
        path: '/health',
        timeout: 30,
        retries: 3
      },
      environment: {
        'TCF_ENV' => 'production',
        'LOG_LEVEL' => 'info'
      }
    }
  end

  describe '#validate_deployment_config' do
    context 'when deployment configuration is valid' do
      it 'validates all deployment requirements' do
        expect(validator).to receive(:validate_image_availability)
          .with('tcf/gateway:v1.2.0')
          .and_return({ available: true, registry: 'docker.io' })

        expect(validator).to receive(:validate_resource_requirements)
          .with(valid_deployment_config[:resources])
          .and_return({ sufficient: true, available_cpu: '2000m', available_memory: '4Gi' })

        expect(validator).to receive(:validate_security_requirements)
          .with(valid_deployment_config)
          .and_return({ secure: true, scanned: true, vulnerabilities: 0 })

        expect(validator).to receive(:validate_health_check_config)
          .with(valid_deployment_config[:health_check])
          .and_return({ valid: true, endpoint_reachable: true })

        result = validator.validate_deployment_config(valid_deployment_config)

        expect(result).to include(
          valid: true,
          image_validation: { available: true },
          resource_validation: { sufficient: true },
          security_validation: { secure: true },
          health_check_validation: { valid: true }
        )
      end

      it 'validates environment variables security' do
        config_with_secrets = valid_deployment_config.merge(
          environment: {
            'TCF_ENV' => 'production',
            'DATABASE_PASSWORD' => 'secretpassword123',
            'API_KEY' => 'sk-1234567890abcdef'
          }
        )

        expect(validator).to receive(:validate_environment_security)
          .with(config_with_secrets[:environment])
          .and_return({ 
            secure: false, 
            violations: ['Plain text password detected', 'API key in environment variables'] 
          })

        result = validator.validate_deployment_config(config_with_secrets)

        expect(result[:valid]).to eq(false)
        expect(result[:security_validation][:violations]).to include('Plain text password detected')
      end
    end

    context 'when deployment configuration is invalid' do
      it 'identifies missing image tag' do
        invalid_config = valid_deployment_config.merge(image: 'tcf/gateway')

        expect(validator).to receive(:validate_image_format)
          .with('tcf/gateway')
          .and_return({ valid: false, error: 'Missing image tag' })

        result = validator.validate_deployment_config(invalid_config)

        expect(result[:valid]).to eq(false)
        expect(result[:errors]).to include('Missing image tag')
      end

      it 'detects insufficient resource allocation' do
        config_with_low_resources = valid_deployment_config.merge(
          resources: { cpu: '10m', memory: '50Mi' }
        )

        expect(validator).to receive(:validate_resource_requirements)
          .with(config_with_low_resources[:resources])
          .and_return({ 
            sufficient: false, 
            errors: ['CPU allocation too low for production', 'Memory allocation insufficient'] 
          })

        result = validator.validate_deployment_config(config_with_low_resources)

        expect(result[:valid]).to eq(false)
        expect(result[:resource_validation][:errors]).to include('CPU allocation too low for production')
      end

      it 'validates replica count constraints' do
        config_with_invalid_replicas = valid_deployment_config.merge(replicas: 0)

        result = validator.validate_deployment_config(config_with_invalid_replicas)

        expect(result[:valid]).to eq(false)
        expect(result[:errors]).to include('Replica count must be greater than 0')
      end
    end
  end

  describe '#validate_pre_deployment_requirements' do
    it 'checks system readiness before deployment' do
      expect(resource_manager).to receive(:check_available_resources)
        .and_return({ cpu: '4000m', memory: '8Gi', disk: '100Gi' })

      expect(docker_manager).to receive(:verify_docker_daemon)
        .and_return({ status: 'running', version: '20.10.0' })

      expect(monitoring_service).to receive(:check_monitoring_system)
        .and_return({ status: 'healthy', prometheus: true, grafana: true })

      expect(security_validator).to receive(:validate_deployment_security)
        .and_return({ secure: true, policies_applied: true })

      result = validator.validate_pre_deployment_requirements

      expect(result).to include(
        ready_for_deployment: true,
        resource_availability: { cpu: '4000m', memory: '8Gi' },
        docker_status: { status: 'running' },
        monitoring_status: { status: 'healthy' },
        security_status: { secure: true }
      )
    end

    it 'identifies system readiness issues' do
      expect(resource_manager).to receive(:check_available_resources)
        .and_return({ cpu: '100m', memory: '500Mi', disk: '10Gi' })

      expect(docker_manager).to receive(:verify_docker_daemon)
        .and_return({ status: 'error', error: 'Docker daemon not responding' })

      result = validator.validate_pre_deployment_requirements

      expect(result[:ready_for_deployment]).to eq(false)
      expect(result[:blocking_issues]).to include('Insufficient CPU resources', 'Docker daemon not responding')
    end
  end

  describe '#validate_image_availability' do
    it 'verifies image exists in registry' do
      expect(docker_manager).to receive(:check_image_exists)
        .with('tcf/gateway:v1.2.0')
        .and_return({ exists: true, registry: 'docker.io', size: '500MB' })

      expect(security_validator).to receive(:scan_image_vulnerabilities)
        .with('tcf/gateway:v1.2.0')
        .and_return({ vulnerabilities: 0, scanned: true, last_scan: Time.now.iso8601 })

      result = validator.validate_image_availability('tcf/gateway:v1.2.0')

      expect(result).to include(
        available: true,
        registry: 'docker.io',
        size: '500MB',
        security_scan: { vulnerabilities: 0, scanned: true }
      )
    end

    it 'handles image not found in registry' do
      expect(docker_manager).to receive(:check_image_exists)
        .with('tcf/nonexistent:latest')
        .and_return({ exists: false, error: 'Image not found' })

      result = validator.validate_image_availability('tcf/nonexistent:latest')

      expect(result[:available]).to eq(false)
      expect(result[:error]).to eq('Image not found')
    end

    it 'identifies security vulnerabilities in image' do
      expect(docker_manager).to receive(:check_image_exists)
        .and_return({ exists: true, registry: 'docker.io' })

      expect(security_validator).to receive(:scan_image_vulnerabilities)
        .and_return({ 
          vulnerabilities: 5, 
          critical: 2, 
          high: 3,
          details: [
            { cve: 'CVE-2023-1234', severity: 'critical', package: 'openssl' },
            { cve: 'CVE-2023-5678', severity: 'high', package: 'curl' }
          ]
        })

      result = validator.validate_image_availability('tcf/gateway:v1.0.0')

      expect(result[:available]).to eq(false)
      expect(result[:security_issues]).to include('2 critical vulnerabilities found')
    end
  end

  describe '#validate_resource_requirements' do
    it 'validates sufficient system resources' do
      resource_config = { cpu: '500m', memory: '1Gi' }

      expect(resource_manager).to receive(:get_available_resources)
        .and_return({ cpu: '4000m', memory: '8Gi', nodes: 3 })

      result = validator.validate_resource_requirements(resource_config)

      expect(result).to include(
        sufficient: true,
        requested: resource_config,
        available: { cpu: '4000m', memory: '8Gi' },
        utilization_after_deployment: { cpu: '12.5%', memory: '12.5%' }
      )
    end

    it 'identifies insufficient resources' do
      resource_config = { cpu: '5000m', memory: '10Gi' }

      expect(resource_manager).to receive(:get_available_resources)
        .and_return({ cpu: '2000m', memory: '4Gi', nodes: 1 })

      result = validator.validate_resource_requirements(resource_config)

      expect(result[:sufficient]).to eq(false)
      expect(result[:errors]).to include('Insufficient CPU: requested 5000m, available 2000m')
      expect(result[:errors]).to include('Insufficient memory: requested 10Gi, available 4Gi')
    end

    it 'validates resource limits and requests' do
      resource_config = {
        requests: { cpu: '100m', memory: '128Mi' },
        limits: { cpu: '500m', memory: '1Gi' }
      }

      result = validator.validate_resource_requirements(resource_config)

      expect(result[:limits_valid]).to eq(true)
      expect(result[:requests_within_limits]).to eq(true)
    end
  end

  describe '#validate_health_check_config' do
    it 'validates health check endpoint configuration' do
      health_config = {
        path: '/health',
        port: 8080,
        timeout: 30,
        retries: 3,
        interval: 10
      }

      expect(validator).to receive(:test_health_endpoint)
        .with('/health', 8080)
        .and_return({ reachable: true, response_time: 25 })

      result = validator.validate_health_check_config(health_config)

      expect(result).to include(
        valid: true,
        endpoint_reachable: true,
        response_time: 25,
        configuration: health_config
      )
    end

    it 'identifies invalid health check configuration' do
      invalid_health_config = {
        path: '/nonexistent',
        timeout: -5,
        retries: 0
      }

      result = validator.validate_health_check_config(invalid_health_config)

      expect(result[:valid]).to eq(false)
      expect(result[:errors]).to include('Invalid timeout value: must be positive')
      expect(result[:errors]).to include('Invalid retry count: must be greater than 0')
    end

    it 'tests health endpoint accessibility' do
      health_config = { path: '/health', port: 8080 }

      expect(validator).to receive(:test_health_endpoint)
        .with('/health', 8080)
        .and_return({ reachable: false, error: 'Connection refused' })

      result = validator.validate_health_check_config(health_config)

      expect(result[:endpoint_reachable]).to eq(false)
      expect(result[:endpoint_error]).to eq('Connection refused')
    end
  end

  describe '#validate_deployment_dependencies' do
    it 'checks required services are running' do
      dependencies = ['postgres', 'redis', 'monitoring']

      expect(docker_manager).to receive(:check_service_status)
        .with('postgres')
        .and_return({ status: 'running', health: 'healthy' })

      expect(docker_manager).to receive(:check_service_status)
        .with('redis')
        .and_return({ status: 'running', health: 'healthy' })

      expect(docker_manager).to receive(:check_service_status)
        .with('monitoring')
        .and_return({ status: 'running', health: 'healthy' })

      result = validator.validate_deployment_dependencies(dependencies)

      expect(result).to include(
        all_dependencies_ready: true,
        dependency_status: {
          'postgres' => { status: 'running', health: 'healthy' },
          'redis' => { status: 'running', health: 'healthy' },
          'monitoring' => { status: 'running', health: 'healthy' }
        }
      )
    end

    it 'identifies missing or unhealthy dependencies' do
      dependencies = ['postgres', 'redis']

      expect(docker_manager).to receive(:check_service_status)
        .with('postgres')
        .and_return({ status: 'stopped', health: 'unhealthy' })

      expect(docker_manager).to receive(:check_service_status)
        .with('redis')
        .and_return({ status: 'error', error: 'Service not found' })

      result = validator.validate_deployment_dependencies(dependencies)

      expect(result[:all_dependencies_ready]).to eq(false)
      expect(result[:missing_dependencies]).to include('postgres', 'redis')
    end
  end

  describe '#validate_rollback_readiness' do
    it 'ensures rollback capability is available' do
      expect(docker_manager).to receive(:get_previous_deployment)
        .with('gateway')
        .and_return({ 
          version: 'v1.1.0', 
          image: 'tcf/gateway:v1.1.0',
          status: 'stopped',
          backup_available: true
        })

      expect(docker_manager).to receive(:verify_rollback_image)
        .with('tcf/gateway:v1.1.0')
        .and_return({ available: true, tested: true })

      result = validator.validate_rollback_readiness('gateway')

      expect(result).to include(
        rollback_ready: true,
        previous_version: 'v1.1.0',
        rollback_image: 'tcf/gateway:v1.1.0',
        backup_available: true
      )
    end

    it 'identifies rollback readiness issues' do
      expect(docker_manager).to receive(:get_previous_deployment)
        .with('gateway')
        .and_return({ status: 'not_found' })

      result = validator.validate_rollback_readiness('gateway')

      expect(result[:rollback_ready]).to eq(false)
      expect(result[:issues]).to include('No previous deployment found for rollback')
    end
  end
end