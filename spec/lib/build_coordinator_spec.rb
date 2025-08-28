# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/build_coordinator'
require_relative '../../lib/repository_manager'

RSpec.describe TcfPlatform::BuildCoordinator do
  let(:repository_manager) { instance_double(TcfPlatform::RepositoryManager) }
  let(:config_manager) { instance_double('ConfigManager') }
  let(:build_coordinator) { described_class.new(repository_manager, config_manager) }

  let(:build_dependencies) do
    {
      'tcf-gateway' => ['tcf-personas', 'tcf-workflows', 'tcf-projects', 'tcf-context', 'tcf-tokens'],
      'tcf-personas' => [],
      'tcf-workflows' => ['tcf-personas'],
      'tcf-projects' => ['tcf-context'],
      'tcf-context' => [],
      'tcf-tokens' => []
    }
  end

  let(:repository_status) do
    {
      'tcf-gateway' => { exists: true, path: '/Users/tcaruso/src/tcf-gateway' },
      'tcf-personas' => { exists: true, path: '/Users/tcaruso/src/tcf-personas' },
      'tcf-workflows' => { exists: true, path: '/Users/tcaruso/src/tcf-workflows' },
      'tcf-projects' => { exists: true, path: '/Users/tcaruso/src/tcf-projects' },
      'tcf-context' => { exists: true, path: '/Users/tcaruso/src/tcf-context' },
      'tcf-tokens' => { exists: true, path: '/Users/tcaruso/src/tcf-tokens' }
    }
  end

  before do
    allow(config_manager).to receive(:build_dependencies).and_return(build_dependencies)
    allow(repository_manager).to receive(:repository_status).and_return(repository_status)
  end

  describe '#analyze_dependencies' do
    it 'determines build order based on service dependencies' do
      dependencies = build_coordinator.analyze_dependencies

      aggregate_failures do
        expect(dependencies).to include(
          'tcf-gateway' => ['tcf-personas', 'tcf-workflows', 'tcf-projects', 'tcf-context', 'tcf-tokens'],
          'tcf-personas' => [],
          'tcf-workflows' => ['tcf-personas']
        )
        expect(dependencies['tcf-projects']).to include('tcf-context')
      end
    end

    it 'identifies services with no dependencies' do
      dependencies = build_coordinator.analyze_dependencies
      independent_services = dependencies.select { |_, deps| deps.empty? }

      aggregate_failures do
        expect(independent_services.keys).to include('tcf-personas', 'tcf-context', 'tcf-tokens')
        expect(independent_services.size).to be >= 3
      end
    end

    context 'when circular dependencies exist' do
      let(:circular_dependencies) do
        {
          'service-a' => ['service-b'],
          'service-b' => ['service-c'],
          'service-c' => ['service-a']
        }
      end

      before do
        allow(config_manager).to receive(:build_dependencies).and_return(circular_dependencies)
      end

      it 'detects circular dependencies and raises error' do
        expect {
          build_coordinator.analyze_dependencies
        }.to raise_error(TcfPlatform::CircularDependencyError, /Circular dependency detected/)
      end

      it 'provides details about the circular dependency' do
        begin
          build_coordinator.analyze_dependencies
        rescue TcfPlatform::CircularDependencyError => e
          expect(e.message).to include('service-a', 'service-b', 'service-c')
        end
      end
    end
  end

  describe '#calculate_build_order' do
    it 'calculates correct build order respecting dependencies' do
      build_order = build_coordinator.calculate_build_order

      aggregate_failures do
        # Independent services can be built first
        expect(build_order.first(3)).to include('tcf-personas', 'tcf-context', 'tcf-tokens')

        # Gateway must be built after all its dependencies
        gateway_index = build_order.index('tcf-gateway')
        personas_index = build_order.index('tcf-personas')
        workflows_index = build_order.index('tcf-workflows')

        expect(gateway_index).to be > personas_index
        expect(gateway_index).to be > workflows_index
      end
    end

    it 'ensures dependencies are built before dependents' do
      build_order = build_coordinator.calculate_build_order

      # tcf-workflows depends on tcf-personas
      workflows_index = build_order.index('tcf-workflows')
      personas_index = build_order.index('tcf-personas')
      expect(workflows_index).to be > personas_index

      # tcf-projects depends on tcf-context
      projects_index = build_order.index('tcf-projects')
      context_index = build_order.index('tcf-context')
      expect(projects_index).to be > context_index
    end

    context 'when specific services requested' do
      it 'calculates build order for requested services only' do
        build_order = build_coordinator.calculate_build_order(['tcf-workflows', 'tcf-personas'])

        aggregate_failures do
          expect(build_order).to contain_exactly('tcf-personas', 'tcf-workflows')
          expect(build_order.index('tcf-workflows')).to be > build_order.index('tcf-personas')
        end
      end

      it 'includes dependencies even if not explicitly requested' do
        build_order = build_coordinator.calculate_build_order(['tcf-workflows'])

        aggregate_failures do
          expect(build_order).to include('tcf-personas') # Dependency of tcf-workflows
          expect(build_order).to include('tcf-workflows') # Explicitly requested
        end
      end
    end
  end

  describe '#build_services' do
    let(:services_to_build) { ['tcf-personas', 'tcf-gateway'] }

    context 'when building succeeds' do
      before do
        allow(build_coordinator).to receive(:calculate_build_order).and_return(['tcf-personas', 'tcf-workflows', 'tcf-projects', 'tcf-context', 'tcf-tokens', 'tcf-gateway'])
        allow(build_coordinator).to receive(:build_single_service).and_return({
          status: 'success',
          image_id: 'sha256:abc123',
          build_time: 45.2,
          size_mb: 150.5
        })
      end

      it 'builds services in dependency order' do
        build_order = []
        allow(build_coordinator).to receive(:build_single_service) do |service_name|
          build_order << service_name
          { status: 'success', image_id: "sha256:#{service_name}", build_time: 30.0, size_mb: 100.0 }
        end

        build_coordinator.build_services(services_to_build)
        expect(build_order.first).to eq('tcf-personas') # No dependencies
        expect(build_order.last).to eq('tcf-gateway') # Has all dependencies
      end

      it 'returns build results for all services' do
        result = build_coordinator.build_services(services_to_build)

        aggregate_failures do
          expect(result).to have_key('tcf-personas')
          expect(result['tcf-personas'][:status]).to eq('success')
          expect(result['tcf-personas'][:image_id]).to include('sha256:')
          expect(result['tcf-personas'][:build_time]).to be_a(Numeric)
        end
      end

      it 'includes build timing and size information' do
        result = build_coordinator.build_services(services_to_build)

        aggregate_failures do
          expect(result['tcf-personas']).to include(
            build_time: be_a(Numeric),
            size_mb: be_a(Numeric),
            image_id: match(/sha256:/)
          )
        end
      end
    end

    context 'when some builds fail' do
      before do
        allow(build_coordinator).to receive(:calculate_build_order).and_return(['tcf-personas', 'tcf-workflows', 'tcf-gateway'])
        allow(build_coordinator).to receive(:build_single_service) do |service_name|
          if service_name == 'tcf-personas'
            raise StandardError, 'Build failed: Missing dependency'
          else
            { status: 'success', image_id: "sha256:#{service_name}", build_time: 30.0, size_mb: 100.0 }
          end
        end
      end

      it 'handles build failures and continues with independent services' do
        result = build_coordinator.build_services(['tcf-personas', 'tcf-workflows'])

        aggregate_failures do
          expect(result['tcf-personas'][:status]).to eq('failed')
          expect(result['tcf-personas'][:error]).to include('Build failed')
          expect(result['tcf-workflows'][:status]).to eq('success') # Independent of failed service
        end
      end

      it 'skips services that depend on failed builds' do
        result = build_coordinator.build_services(['tcf-personas', 'tcf-workflows', 'tcf-gateway'])

        aggregate_failures do
          expect(result['tcf-personas'][:status]).to eq('failed')
          expect(result['tcf-workflows'][:status]).to eq('success') # Independent
          expect(result['tcf-gateway'][:status]).to eq('skipped') # Depends on failed tcf-personas
          expect(result['tcf-gateway'][:reason]).to include('dependency failed')
        end
      end
    end

    context 'when repository does not exist' do
      let(:missing_repo_status) do
        repository_status.merge('tcf-personas' => { exists: false })
      end

      before do
        allow(repository_manager).to receive(:repository_status).and_return(missing_repo_status)
      end

      it 'skips building services with missing repositories' do
        result = build_coordinator.build_services(['tcf-personas'])

        aggregate_failures do
          expect(result['tcf-personas'][:status]).to eq('skipped')
          expect(result['tcf-personas'][:reason]).to include('repository not found')
        end
      end
    end
  end

  describe '#parallel_build' do
    let(:independent_services) { ['tcf-personas', 'tcf-context', 'tcf-tokens'] }

    context 'when parallel building succeeds' do
      before do
        allow(build_coordinator).to receive(:build_single_service) do |service_name|
          sleep(0.1) # Simulate build time
          { status: 'success', image_id: "sha256:#{service_name}", build_time: 0.1, size_mb: 100.0 }
        end
      end

      it 'builds independent services in parallel' do
        start_times = {}
        allow(build_coordinator).to receive(:build_single_service) do |service_name|
          start_times[service_name] = Time.now
          sleep(0.1)
          { status: 'success', image_id: "sha256:#{service_name}", build_time: 0.1, size_mb: 100.0 }
        end

        build_coordinator.parallel_build(independent_services)

        # Verify builds started within reasonable time window (parallel execution)
        time_diffs = start_times.values.map { |time| (time - start_times.values.min).abs }
        expect(time_diffs.max).to be < 0.05 # All started nearly simultaneously
      end

      it 'returns results for all parallel builds' do
        result = build_coordinator.parallel_build(independent_services)

        aggregate_failures do
          expect(result.keys).to contain_exactly(*independent_services)
          expect(result.values).to all(include(status: 'success'))
        end
      end

      it 'builds faster than sequential builds' do
        sequential_start = Time.now
        build_coordinator.build_services(independent_services)
        sequential_time = Time.now - sequential_start

        parallel_start = Time.now
        build_coordinator.parallel_build(independent_services)
        parallel_time = Time.now - parallel_start

        # Parallel should be significantly faster than sequential
        # With 0.1s sleep per service, 3 services should take ~0.3s sequential vs ~0.1s parallel
        expect(parallel_time).to be < (sequential_time * 0.7)
      end
    end

    context 'when some parallel builds fail' do
      before do
        allow(build_coordinator).to receive(:build_single_service) do |service_name|
          if service_name == 'tcf-context'
            raise StandardError, 'Parallel build failure'
          else
            { status: 'success', image_id: "sha256:#{service_name}", build_time: 0.1, size_mb: 100.0 }
          end
        end
      end

      it 'handles parallel build failures independently' do
        result = build_coordinator.parallel_build(independent_services)

        aggregate_failures do
          expect(result['tcf-context'][:status]).to eq('failed')
          expect(result['tcf-personas'][:status]).to eq('success')
          expect(result['tcf-tokens'][:status]).to eq('success')
        end
      end
    end
  end

  describe '#build_status' do
    before do
      allow(build_coordinator).to receive(:get_docker_images).and_return({
        'tcf-gateway' => {
          image_id: 'sha256:gateway123',
          created: Time.now - 3600,
          size_mb: 200.5
        },
        'tcf-personas' => {
          image_id: 'sha256:personas456',
          created: Time.now - 7200,
          size_mb: 150.2
        }
      })
    end

    it 'provides comprehensive build status for all services' do
      status = build_coordinator.build_status

      aggregate_failures do
        expect(status).to have_key('tcf-gateway')
        expect(status['tcf-gateway']).to include(
          image_id: 'sha256:gateway123',
          size_mb: 200.5
        )
        expect(status['tcf-gateway'][:created]).to be_a(Time)
      end
    end

    it 'identifies services without built images' do
      allow(build_coordinator).to receive(:get_docker_images).and_return({
        'tcf-gateway' => { image_id: 'sha256:gateway123', created: Time.now, size_mb: 200.5 }
      })

      status = build_coordinator.build_status

      aggregate_failures do
        expect(status['tcf-gateway'][:status]).to eq('built')
        expect(status['tcf-personas'][:status]).to eq('not_built')
        expect(status['tcf-personas'][:image_id]).to be_nil
      end
    end

    it 'includes build age and freshness information' do
      status = build_coordinator.build_status

      aggregate_failures do
        expect(status['tcf-gateway'][:age_hours]).to be_within(0.1).of(1.0)
        expect(status['tcf-personas'][:age_hours]).to be_within(0.1).of(2.0)
      end
    end
  end
end