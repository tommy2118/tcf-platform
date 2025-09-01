# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/blue_green_deployer'
require_relative '../../lib/deployment_validator'

RSpec.describe TcfPlatform::BlueGreenDeployer do
  let(:docker_manager) { instance_double('TcfPlatform::DockerManager') }
  let(:monitoring_service) { instance_double('TcfPlatform::MonitoringService') }
  let(:deployment_validator) { instance_double('TcfPlatform::DeploymentValidator') }
  let(:load_balancer) { instance_double('TcfPlatform::LoadBalancer') }
  
  let(:deployer) do
    described_class.new(
      docker_manager: docker_manager,
      monitoring_service: monitoring_service,
      deployment_validator: deployment_validator,
      load_balancer: load_balancer
    )
  end

  let(:deployment_config) do
    {
      image: 'tcf/gateway:v1.2.0',
      service: 'gateway',
      replicas: 2,
      health_check_timeout: 60,
      traffic_switch_strategy: 'gradual',
      rollback_on_failure: true
    }
  end

  describe '#deploy' do
    context 'when performing blue-green deployment' do
      it 'creates green environment and validates health' do
        expect(deployment_validator).to receive(:validate_deployment_config)
          .with(deployment_config)
          .and_return({ valid: true })

        expect(docker_manager).to receive(:create_service)
          .with(deployment_config[:service], deployment_config[:image], suffix: 'green')
          .and_return({ status: 'success', service_id: 'gateway-green' })

        expect(docker_manager).to receive(:wait_for_service_health)
          .with('gateway-green', timeout: 60)
          .and_return({ healthy: true, response_time: 50 })

        expect(monitoring_service).to receive(:validate_service_metrics)
          .with('gateway-green')
          .and_return({ status: 'healthy', cpu_usage: 25, memory_usage: 45 })

        result = deployer.deploy(deployment_config)

        expect(result).to include(
          status: 'success',
          green_environment: { service_id: 'gateway-green', healthy: true },
          deployment_time: be_within(5).of(Time.now.to_i)
        )
      end

      it 'performs zero-downtime deployment within 5 seconds' do
        allow(deployment_validator).to receive(:validate_deployment_config).and_return({ valid: true })
        allow(docker_manager).to receive(:create_service).and_return({ status: 'success', service_id: 'gateway-green' })
        allow(docker_manager).to receive(:wait_for_service_health).and_return({ healthy: true })
        allow(monitoring_service).to receive(:validate_service_metrics).and_return({ status: 'healthy' })

        start_time = Time.now
        deployer.deploy(deployment_config)
        deployment_duration = Time.now - start_time

        expect(deployment_duration).to be < 5.0
      end

      it 'automatically rolls back on green environment health failure' do
        expect(deployment_validator).to receive(:validate_deployment_config).and_return({ valid: true })
        expect(docker_manager).to receive(:create_service).and_return({ status: 'success', service_id: 'gateway-green' })
        expect(docker_manager).to receive(:wait_for_service_health).and_return({ healthy: false, error: 'Service unhealthy' })
        expect(deployer).to receive(:rollback).with(deployment_config[:service], reason: 'Green environment health check failed')

        result = deployer.deploy(deployment_config)

        expect(result).to include(
          status: 'failed',
          reason: 'Green environment health check failed',
          rollback_performed: true
        )
      end

      it 'handles container startup failures gracefully' do
        expect(deployment_validator).to receive(:validate_deployment_config).and_return({ valid: true })
        expect(docker_manager).to receive(:create_service)
          .and_raise(TcfPlatform::ContainerStartupError, 'Failed to start container: port already in use')

        result = deployer.deploy(deployment_config)

        expect(result).to include(
          status: 'failed',
          error: 'Failed to start container: port already in use',
          rollback_performed: false
        )
      end

      it 'validates deployment config before starting' do
        allow(docker_manager).to receive(:create_service)
        expect(deployment_validator).to receive(:validate_deployment_config)
          .with(deployment_config)
          .and_return({ valid: false, errors: ['Missing required image tag', 'Invalid replica count'] })

        result = deployer.deploy(deployment_config)

        expect(result).to include(
          status: 'failed',
          validation_errors: ['Missing required image tag', 'Invalid replica count']
        )
        expect(docker_manager).not_to have_received(:create_service)
      end
    end

    context 'when deployment validation fails' do
      it 'prevents deployment with invalid configuration' do
        allow(docker_manager).to receive(:create_service)
        expect(deployment_validator).to receive(:validate_deployment_config)
          .and_return({ 
            valid: false, 
            errors: ['Image not found in registry', 'Insufficient resources'] 
          })

        result = deployer.deploy(deployment_config)

        expect(result[:status]).to eq('failed')
        expect(result[:validation_errors]).to include('Image not found in registry', 'Insufficient resources')
        expect(docker_manager).not_to have_received(:create_service)
      end
    end
  end

  describe '#rollback' do
    context 'when performing automatic rollback' do
      it 'switches traffic back to blue environment' do
        expect(load_balancer).to receive(:get_current_target)
          .with('gateway')
          .and_return('gateway-green')

        expect(load_balancer).to receive(:switch_traffic)
          .with('gateway', from: 'gateway-green', to: 'gateway-blue')
          .and_return({ status: 'success', switch_time: 2.5 })

        expect(docker_manager).to receive(:remove_service)
          .with('gateway-green')
          .and_return({ status: 'success' })

        result = deployer.rollback('gateway', reason: 'Health check failure')

        expect(result).to include(
          status: 'success',
          reason: 'Health check failure',
          traffic_switched_to: 'gateway-blue',
          rollback_time: be_within(5).of(Time.now.to_i)
        )
      end

      it 'rolls back to specific deployment version' do
        deployment_history = {
          'v1.1.0' => { service_id: 'gateway-v1-1-0', status: 'stopped' },
          'v1.0.0' => { service_id: 'gateway-v1-0-0', status: 'stopped' }
        }

        expect(docker_manager).to receive(:get_deployment_history)
          .with('gateway')
          .and_return(deployment_history)

        expect(docker_manager).to receive(:restart_service)
          .with('gateway-v1-1-0')
          .and_return({ status: 'success', healthy: true })

        expect(load_balancer).to receive(:switch_traffic)
          .with('gateway', to: 'gateway-v1-1-0')
          .and_return({ status: 'success' })

        result = deployer.rollback('gateway', version: 'v1.1.0')

        expect(result).to include(
          status: 'success',
          rolled_back_to: 'v1.1.0',
          service_id: 'gateway-v1-1-0'
        )
      end

      it 'handles rollback failures gracefully' do
        expect(load_balancer).to receive(:switch_traffic)
          .and_raise(TcfPlatform::LoadBalancerError, 'Traffic switch failed')

        result = deployer.rollback('gateway', reason: 'Manual rollback')

        expect(result).to include(
          status: 'failed',
          error: 'Traffic switch failed',
          manual_intervention_required: true
        )
      end
    end

    context 'when performing manual rollback' do
      it 'executes manual rollback with confirmation' do
        expect(deployer).to receive(:confirm_manual_rollback)
          .with('gateway')
          .and_return(true)

        expect(load_balancer).to receive(:switch_traffic)
          .with('gateway', from: 'gateway-green', to: 'gateway-blue')
          .and_return({ status: 'success' })

        result = deployer.rollback('gateway', manual: true)

        expect(result[:status]).to eq('success')
        expect(result[:manual_confirmation]).to eq(true)
      end
    end
  end

  describe '#traffic_switch' do
    context 'when performing gradual traffic switching' do
      it 'switches traffic in percentage increments' do
        traffic_percentages = [10, 25, 50, 75, 100]

        traffic_percentages.each do |percentage|
          expect(load_balancer).to receive(:set_traffic_percentage)
            .with('gateway', 'gateway-green', percentage)
            .and_return({ status: 'success', current_percentage: percentage })

          expect(monitoring_service).to receive(:monitor_traffic_metrics)
            .with('gateway-green', duration: 30)
            .and_return({ error_rate: 0.01, response_time: 45 })
        end

        result = deployer.traffic_switch('gateway', from: 'gateway-blue', to: 'gateway-green', strategy: 'gradual')

        expect(result).to include(
          status: 'success',
          final_percentage: 100,
          switch_completed: true,
          total_switch_time: be > 0
        )
      end

      it 'monitors error rates during traffic switching' do
        expect(load_balancer).to receive(:set_traffic_percentage).and_return({ status: 'success' })
        expect(monitoring_service).to receive(:monitor_traffic_metrics)
          .and_return({ error_rate: 0.15, response_time: 200 })

        expect(deployer).to receive(:rollback)
          .with('gateway', reason: 'High error rate during traffic switch')

        result = deployer.traffic_switch('gateway', from: 'gateway-blue', to: 'gateway-green')

        expect(result).to include(
          status: 'failed',
          reason: 'High error rate during traffic switch',
          error_rate: 0.15,
          rollback_triggered: true
        )
      end

      it 'performs instant traffic switch when specified' do
        expect(load_balancer).to receive(:switch_traffic_instant)
          .with('gateway', from: 'gateway-blue', to: 'gateway-green')
          .and_return({ status: 'success', switch_time: 0.5 })

        result = deployer.traffic_switch('gateway', from: 'gateway-blue', to: 'gateway-green', strategy: 'instant')

        expect(result).to include(
          status: 'success',
          switch_time: 0.5,
          strategy_used: 'instant'
        )
      end

      it 'handles traffic switch validation failure' do
        expect(load_balancer).to receive(:validate_traffic_switch)
          .with('gateway', 'gateway-green')
          .and_return({ valid: false, reason: 'Target service not responding' })

        result = deployer.traffic_switch('gateway', from: 'gateway-blue', to: 'gateway-green')

        expect(result).to include(
          status: 'failed',
          validation_error: 'Target service not responding'
        )
      end
    end

    context 'when traffic switch fails' do
      it 'automatically reverts traffic on switch failure' do
        expect(load_balancer).to receive(:set_traffic_percentage)
          .with('gateway', 'gateway-green', 10)
          .and_return({ status: 'success' })

        expect(load_balancer).to receive(:set_traffic_percentage)
          .with('gateway', 'gateway-green', 25)
          .and_raise(TcfPlatform::TrafficSwitchError, 'Load balancer timeout')

        expect(load_balancer).to receive(:revert_traffic)
          .with('gateway', to: 'gateway-blue')
          .and_return({ status: 'success' })

        result = deployer.traffic_switch('gateway', from: 'gateway-blue', to: 'gateway-green')

        expect(result).to include(
          status: 'failed',
          error: 'Load balancer timeout',
          traffic_reverted: true
        )
      end
    end
  end

  describe '#deployment_status' do
    it 'returns current deployment status' do
      expect(docker_manager).to receive(:get_service_status)
        .with('gateway')
        .and_return({
          blue: { service_id: 'gateway-blue', status: 'running', traffic_percentage: 0 },
          green: { service_id: 'gateway-green', status: 'running', traffic_percentage: 100 }
        })

      expect(load_balancer).to receive(:get_traffic_distribution)
        .with('gateway')
        .and_return({ 'gateway-blue' => 0, 'gateway-green' => 100 })

      result = deployer.deployment_status('gateway')

      expect(result).to include(
        current_environment: 'green',
        blue_status: { status: 'running', traffic_percentage: 0 },
        green_status: { status: 'running', traffic_percentage: 100 }
      )
    end
  end

  describe '#health_check' do
    it 'validates health of both blue and green environments' do
      expect(monitoring_service).to receive(:check_service_health)
        .with('gateway-blue')
        .and_return({ healthy: true, response_time: 30 })

      expect(monitoring_service).to receive(:check_service_health)
        .with('gateway-green')
        .and_return({ healthy: true, response_time: 35 })

      result = deployer.health_check('gateway')

      expect(result).to include(
        blue_health: { healthy: true, response_time: 30 },
        green_health: { healthy: true, response_time: 35 },
        overall_health: 'healthy'
      )
    end
  end
end