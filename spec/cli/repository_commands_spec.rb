# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/cli/repository_commands'

RSpec.describe TcfPlatform::RepositoryCommands do
  let(:cli_class) do
    Class.new(Thor) do
      include TcfPlatform::RepositoryCommands
    end
  end
  let(:cli) { cli_class.new }
  let(:repository_manager) { instance_double(TcfPlatform::RepositoryManager) }
  let(:build_coordinator) { instance_double(TcfPlatform::BuildCoordinator) }

  before do
    allow(cli).to receive(:repository_manager).and_return(repository_manager)
    allow(cli).to receive(:build_coordinator).and_return(build_coordinator)
    allow($stdout).to receive(:puts)
  end

  describe '#repos' do
    context 'with status subcommand' do
      let(:repository_status) do
        {
          'tcf-gateway' => {
            exists: true,
            path: '/Users/tcaruso/src/tcf-gateway',
            git_repository: true,
            current_branch: 'master',
            clean: true,
            latest_commit: {
              hash: 'abc123',
              message: 'Latest commit',
              author: 'Dev Team',
              date: Time.parse('2024-01-15 10:30:00')
            }
          },
          'tcf-personas' => {
            exists: false,
            path: '/Users/tcaruso/src/tcf-personas',
            git_repository: false,
            current_branch: nil,
            clean: nil
          }
        }
      end

      before do
        allow(repository_manager).to receive(:repository_status).and_return(repository_status)
      end

      it 'displays comprehensive repository status information' do
        cli.repos('status')

        aggregate_failures do
          expect($stdout).to have_received(:puts).with(/📋 TCF Platform Repository Status/)
          expect($stdout).to have_received(:puts).with(/tcf-gateway.*master.*abc123/)
          expect($stdout).to have_received(:puts).with(/tcf-personas.*Missing/)
        end
      end

      it 'shows repository paths and git status' do
        cli.repos('status')

        aggregate_failures do
          expect($stdout).to have_received(:puts).with(/\/Users\/tcaruso\/src\/tcf-gateway/)
          expect($stdout).to have_received(:puts).with(/Clean working directory/)
          expect($stdout).to have_received(:puts).with(/Latest commit/)
        end
      end

      it 'identifies missing repositories' do
        cli.repos('status')

        expect($stdout).to have_received(:puts).with(/⚠️.*Missing repositories found/)
      end
    end

    context 'with clone subcommand' do
      let(:clone_results) do
        {
          'tcf-personas' => {
            status: 'cloned',
            path: '/Users/tcaruso/src/tcf-personas',
            url: 'git@github.com:tommy2118/tcf-personas.git'
          },
          'tcf-workflows' => {
            status: 'failed',
            path: '/Users/tcaruso/src/tcf-workflows',
            error: 'Permission denied'
          }
        }
      end

      before do
        allow(repository_manager).to receive(:clone_missing_repositories).and_return(clone_results)
      end

      it 'clones all missing repositories by default' do
        cli.repos('clone')

        aggregate_failures do
          expect(repository_manager).to have_received(:clone_missing_repositories).with(nil)
          expect($stdout).to have_received(:puts).with(/🔄 Cloning missing repositories/)
          expect($stdout).to have_received(:puts).with(/✅.*tcf-personas.*cloned/)
          expect($stdout).to have_received(:puts).with(/❌.*tcf-workflows.*failed/)
        end
      end

      it 'clones specific repositories when requested' do
        allow(repository_manager).to receive(:clone_missing_repositories).with(['tcf-personas']).and_return({
          'tcf-personas' => {
            status: 'cloned',
            path: '/Users/tcaruso/src/tcf-personas',
            url: 'git@github.com:tommy2118/tcf-personas.git'
          }
        })

        cli.repos('clone', 'tcf-personas')

        expect(repository_manager).to have_received(:clone_missing_repositories).with(['tcf-personas'])
      end

      it 'displays clone progress and results' do
        cli.repos('clone')

        aggregate_failures do
          expect($stdout).to have_received(:puts).with(/Repository cloning completed/)
          expect($stdout).to have_received(:puts).with(/1 successful, 1 failed/)
        end
      end
    end

    context 'with update subcommand' do
      let(:update_results) do
        {
          'tcf-gateway' => {
            status: 'updated',
            path: '/Users/tcaruso/src/tcf-gateway',
            latest_commit: {
              hash: 'def456',
              message: 'Updated commit',
              author: 'Developer',
              date: Time.parse('2024-01-15 11:00:00')
            }
          },
          'tcf-personas' => {
            status: 'failed',
            path: '/Users/tcaruso/src/tcf-personas',
            error: 'Merge conflicts detected'
          }
        }
      end

      before do
        allow(repository_manager).to receive(:update_repositories).and_return(update_results)
      end

      it 'updates all existing repositories by default' do
        cli.repos('update')

        aggregate_failures do
          expect(repository_manager).to have_received(:update_repositories).with(nil)
          expect($stdout).to have_received(:puts).with(/🔄 Updating repositories/)
          expect($stdout).to have_received(:puts).with(/✅.*tcf-gateway.*updated/)
          expect($stdout).to have_received(:puts).with(/❌.*tcf-personas.*failed/)
        end
      end

      it 'updates specific repositories when requested' do
        allow(repository_manager).to receive(:update_repositories).with(['tcf-gateway']).and_return({
          'tcf-gateway' => update_results['tcf-gateway']
        })

        cli.repos('update', 'tcf-gateway')

        expect(repository_manager).to have_received(:update_repositories).with(['tcf-gateway'])
      end

      it 'shows update progress and commit information' do
        cli.repos('update')

        aggregate_failures do
          expect($stdout).to have_received(:puts).with(/Repository updates completed/)
          expect($stdout).to have_received(:puts).with(/def456/)
          expect($stdout).to have_received(:puts).with(/Updated commit/)
        end
      end
    end
  end

  describe '#build' do
    context 'with no arguments' do
      let(:build_results) do
        {
          'tcf-personas' => {
            status: 'success',
            image_id: 'sha256:personas123',
            build_time: 45.2,
            size_mb: 150.5
          },
          'tcf-gateway' => {
            status: 'failed',
            error: 'Build failed: Missing dependency'
          }
        }
      end

      before do
        allow(build_coordinator).to receive(:build_services).and_return(build_results)
        allow(build_coordinator).to receive(:calculate_build_order).and_return(%w[tcf-personas tcf-context tcf-tokens tcf-workflows tcf-projects tcf-gateway])
      end

      it 'builds all TCF services in dependency order' do
        cli.build

        aggregate_failures do
          expect($stdout).to have_received(:puts).with(/🔨 Building TCF Platform services/)
          expect($stdout).to have_received(:puts).with(/Building in dependency order/)
          expect($stdout).to have_received(:puts).with(/✅.*tcf-personas.*success/)
          expect($stdout).to have_received(:puts).with(/❌.*tcf-gateway.*failed/)
        end
      end

      it 'shows build timing and size information' do
        cli.build

        aggregate_failures do
          expect($stdout).to have_received(:puts).with(/tcf-personas.*success.*45.2s/)
          expect($stdout).to have_received(:puts).with(/Total time.*45.2s.*Total size.*150.5/)
          expect($stdout).to have_received(:puts).with(/Build completed/)
        end
      end
    end

    context 'with specific services' do
      let(:build_results) do
        {
          'tcf-personas' => {
            status: 'success',
            image_id: 'sha256:personas456',
            build_time: 30.0,
            size_mb: 120.0
          }
        }
      end

      before do
        allow(build_coordinator).to receive(:build_services).with(['tcf-personas']).and_return(build_results)
        allow(build_coordinator).to receive(:calculate_build_order).with(['tcf-personas']).and_return(['tcf-personas'])
      end

      it 'builds only requested services' do
        cli.build('tcf-personas')

        aggregate_failures do
          expect(build_coordinator).to have_received(:build_services).with(['tcf-personas'])
          expect($stdout).to have_received(:puts).with(/Building services: tcf-personas/)
        end
      end
    end

    context 'with --parallel flag' do
      let(:parallel_build_results) do
        {
          'tcf-personas' => { status: 'success', image_id: 'sha256:personas789', build_time: 25.0, size_mb: 110.0 },
          'tcf-context' => { status: 'success', image_id: 'sha256:context789', build_time: 20.0, size_mb: 95.0 },
          'tcf-tokens' => { status: 'success', image_id: 'sha256:tokens789', build_time: 22.0, size_mb: 85.0 }
        }
      end

      before do
        allow(cli).to receive(:options).and_return({ parallel: true })
        allow(build_coordinator).to receive(:parallel_build).and_return(parallel_build_results)
        allow(build_coordinator).to receive(:analyze_dependencies).and_return({
          'tcf-personas' => [],
          'tcf-context' => [],
          'tcf-tokens' => []
        })
        allow(build_coordinator).to receive(:calculate_build_order).and_return(%w[tcf-personas tcf-context tcf-tokens])
        allow(build_coordinator).to receive(:build_services).and_return({})
      end

      it 'builds independent services in parallel' do
        cli.build

        aggregate_failures do
          expect(build_coordinator).to have_received(:parallel_build)
          expect($stdout).to have_received(:puts).with(/⚡ Building services in parallel/)
          expect($stdout).to have_received(:puts).with(/3 services built successfully/)
        end
      end
    end
  end

  describe '#build_status' do
    let(:build_status) do
      {
        'tcf-gateway' => {
          status: 'built',
          image_id: 'sha256:gateway123',
          created: Time.parse('2024-01-15 09:00:00'),
          size_mb: 200.5,
          age_hours: 2.5
        },
        'tcf-personas' => {
          status: 'not_built',
          image_id: nil,
          created: nil,
          size_mb: nil,
          age_hours: nil
        }
      }
    end

    before do
      allow(build_coordinator).to receive(:build_status).and_return(build_status)
    end

    it 'displays comprehensive build status for all services' do
      cli.build_status

      aggregate_failures do
        expect($stdout).to have_received(:puts).with(/📊 TCF Platform Build Status/)
        expect($stdout).to have_received(:puts).with(/tcf-gateway.*Built.*2.5h ago/)
        expect($stdout).to have_received(:puts).with(/tcf-personas.*Not built/)
        expect($stdout).to have_received(:puts).with(/Total size: 200.5 MB/)
      end
    end

    it 'shows build freshness and image information' do
      cli.build_status

      aggregate_failures do
        expect($stdout).to have_received(:puts).with(/gateway123/)
        expect($stdout).to have_received(:puts).with(/Jan 15, 2024/)
        expect($stdout).to have_received(:puts).with(/Build status summary/)
      end
    end
  end
end