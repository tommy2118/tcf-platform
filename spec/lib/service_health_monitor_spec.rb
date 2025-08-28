# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/service_health_monitor'
require_relative '../../lib/docker_manager'

RSpec.describe TcfPlatform::ServiceHealthMonitor do
  let(:monitor) { described_class.new }
  let(:docker_manager) { instance_double(TcfPlatform::DockerManager) }

  before do
    allow(TcfPlatform::DockerManager).to receive(:new).and_return(docker_manager)
  end

  describe '#aggregate_health_status' do
    context 'when all services are healthy' do
      before do
        allow(docker_manager).to receive(:service_status).and_return({
          gateway: { status: 'running', health: 'healthy' },
          personas: { status: 'running', health: 'healthy' },
          workflows: { status: 'running', health: 'healthy' }
        })
      end

      it 'reports overall status as healthy' do
        result = monitor.aggregate_health_status

        aggregate_failures do
          expect(result[:overall_status]).to eq('healthy')
          expect(result[:healthy_count]).to eq(3)
          expect(result[:unhealthy_count]).to eq(0)
          expect(result[:total_services]).to eq(3)
        end
      end

      it 'includes individual service health details' do
        result = monitor.aggregate_health_status

        expect(result[:services]).to include(
          gateway: { status: 'running', health: 'healthy' },
          personas: { status: 'running', health: 'healthy' },
          workflows: { status: 'running', health: 'healthy' }
        )
      end
    end

    context 'when some services are unhealthy' do
      before do
        allow(docker_manager).to receive(:service_status).and_return({
          gateway: { status: 'running', health: 'healthy' },
          personas: { status: 'exited', health: 'unhealthy' },
          workflows: { status: 'running', health: 'healthy' }
        })
      end

      it 'reports overall status as degraded' do
        result = monitor.aggregate_health_status

        aggregate_failures do
          expect(result[:overall_status]).to eq('degraded')
          expect(result[:healthy_count]).to eq(2)
          expect(result[:unhealthy_count]).to eq(1)
          expect(result[:total_services]).to eq(3)
        end
      end

      it 'identifies unhealthy services' do
        result = monitor.aggregate_health_status

        expect(result[:unhealthy_services]).to contain_exactly(:personas)
      end
    end

    context 'when all services are down' do
      before do
        allow(docker_manager).to receive(:service_status).and_return({
          gateway: { status: 'exited', health: 'unhealthy' },
          personas: { status: 'exited', health: 'unhealthy' },
          workflows: { status: 'exited', health: 'unhealthy' }
        })
      end

      it 'reports overall status as critical' do
        result = monitor.aggregate_health_status

        aggregate_failures do
          expect(result[:overall_status]).to eq('critical')
          expect(result[:healthy_count]).to eq(0)
          expect(result[:unhealthy_count]).to eq(3)
          expect(result[:total_services]).to eq(3)
        end
      end
    end
  end

  describe '#service_uptime' do
    before do
      allow(docker_manager).to receive(:service_uptime).with(:gateway).and_return('2 hours')
      allow(docker_manager).to receive(:service_uptime).with(:personas).and_return('30 minutes')
    end

    it 'returns uptime for individual services' do
      expect(monitor.service_uptime(:gateway)).to eq('2 hours')
      expect(monitor.service_uptime(:personas)).to eq('30 minutes')
    end
  end

  describe '#health_check_history' do
    it 'maintains a history of health checks' do
      # Mock multiple health checks over time
      allow(docker_manager).to receive(:service_status).and_return(
        { gateway: { status: 'running', health: 'healthy' } }
      )

      monitor.aggregate_health_status
      first_check = monitor.health_check_history.last

      expect(first_check).to include(
        timestamp: be_a(Time),
        overall_status: 'healthy',
        healthy_count: 1
      )
    end

    it 'limits history to last 100 entries' do
      allow(docker_manager).to receive(:service_status).and_return({})

      105.times { monitor.aggregate_health_status }

      expect(monitor.health_check_history.size).to eq(100)
    end
  end
end