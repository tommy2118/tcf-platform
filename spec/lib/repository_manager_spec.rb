# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/repository_manager'

RSpec.describe TcfPlatform::RepositoryManager do
  let(:config_manager) { instance_double('ConfigManager') }
  let(:base_path) { '/Users/tcaruso/src' }
  let(:repository_manager) { described_class.new(config_manager, base_path) }

  let(:repository_config) do
    {
      'tcf-gateway' => {
        'url' => 'git@github.com:tommy2118/tcf-gateway.git',
        'branch' => 'master',
        'required' => true
      },
      'tcf-personas' => {
        'url' => 'git@github.com:tommy2118/tcf-personas.git',
        'branch' => 'master',
        'required' => true
      },
      'tcf-workflows' => {
        'url' => 'git@github.com:tommy2118/tcf-workflows.git',
        'branch' => 'master',
        'required' => false
      }
    }
  end

  before do
    allow(config_manager).to receive(:repository_config).and_return(repository_config)
  end

  describe '#discover_repositories' do
    context 'when all repositories exist locally' do
      before do
        allow(Dir).to receive(:exist?).and_return(true)
        allow(File).to receive(:exist?).and_return(true)
        allow(repository_manager).to receive(:git_repository?).and_return(true)
        allow(repository_manager).to receive(:get_current_branch).and_return('master')
        allow(repository_manager).to receive(:working_directory_clean?).and_return(true)
      end

      it 'discovers all TCF repositories with their status' do
        repos = repository_manager.discover_repositories

        aggregate_failures do
          expect(repos).to have_key('tcf-gateway')
          expect(repos['tcf-gateway']).to include(
            path: "#{base_path}/tcf-gateway",
            exists: true,
            git_repository: true,
            current_branch: 'master',
            clean: true
          )
        end
      end

      it 'identifies repository configuration details' do
        repos = repository_manager.discover_repositories

        aggregate_failures do
          expect(repos['tcf-gateway'][:url]).to eq('git@github.com:tommy2118/tcf-gateway.git')
          expect(repos['tcf-gateway'][:required]).to eq(true)
          expect(repos['tcf-personas'][:required]).to eq(true)
          expect(repos['tcf-workflows'][:required]).to eq(false)
        end
      end
    end

    context 'when some repositories are missing' do
      before do
        allow(Dir).to receive(:exist?).with("#{base_path}/tcf-gateway").and_return(true)
        allow(Dir).to receive(:exist?).with("#{base_path}/tcf-personas").and_return(false)
        allow(Dir).to receive(:exist?).with("#{base_path}/tcf-workflows").and_return(true)
        allow(File).to receive(:exist?).and_return(true)
        allow(repository_manager).to receive(:git_repository?).and_return(true)
        allow(repository_manager).to receive(:get_current_branch).and_return('master')
        allow(repository_manager).to receive(:working_directory_clean?).and_return(true)
      end

      it 'identifies missing repositories' do
        repos = repository_manager.discover_repositories
        missing_repos = repos.select { |_, info| !info[:exists] }

        aggregate_failures do
          expect(missing_repos).to have_key('tcf-personas')
          expect(missing_repos['tcf-personas']).to include(
            exists: false,
            path: "#{base_path}/tcf-personas"
          )
        end
      end

      it 'marks existing repositories correctly' do
        repos = repository_manager.discover_repositories

        aggregate_failures do
          expect(repos['tcf-gateway'][:exists]).to eq(true)
          expect(repos['tcf-workflows'][:exists]).to eq(true)
        end
      end
    end

    context 'when directories exist but are not git repositories' do
      before do
        allow(Dir).to receive(:exist?).and_return(true)
        allow(File).to receive(:exist?).and_return(true)
        
        # Set up git repository detection for all repositories
        allow(repository_manager).to receive(:git_repository?).and_return(false)
        allow(repository_manager).to receive(:git_repository?).with("#{base_path}/tcf-gateway").and_return(true)
        allow(repository_manager).to receive(:git_repository?).with("#{base_path}/tcf-personas").and_return(false)
        
        allow(repository_manager).to receive(:get_current_branch).and_return('master')
        allow(repository_manager).to receive(:working_directory_clean?).and_return(true)
      end

      it 'identifies non-git directories' do
        repos = repository_manager.discover_repositories

        aggregate_failures do
          expect(repos['tcf-gateway'][:git_repository]).to eq(true)
          expect(repos['tcf-personas'][:git_repository]).to eq(false)
        end
      end
    end
  end

  describe '#clone_missing_repositories' do
    let(:missing_repos) { ['tcf-personas', 'tcf-workflows'] }

    context 'when cloning succeeds' do
      before do
        allow(repository_manager).to receive(:execute_git_clone).and_return(true)
        allow(repository_manager).to receive(:verify_clone_success).and_return(true)
      end

      it 'clones missing repositories successfully' do
        result = repository_manager.clone_missing_repositories(missing_repos)

        aggregate_failures do
          expect(result).to have_key('tcf-personas')
          expect(result['tcf-personas'][:status]).to eq('cloned')
          expect(result['tcf-personas'][:path]).to eq("#{base_path}/tcf-personas")
        end
      end

      it 'tracks cloning progress for multiple repositories' do
        result = repository_manager.clone_missing_repositories(missing_repos)

        aggregate_failures do
          expect(result).to have_key('tcf-personas')
          expect(result).to have_key('tcf-workflows')
          expect(result.values).to all(include(status: 'cloned'))
        end
      end
    end

    context 'when cloning fails' do
      before do
        allow(repository_manager).to receive(:execute_git_clone)
          .with('tcf-personas', anything, anything)
          .and_raise(StandardError, 'Permission denied')
        allow(repository_manager).to receive(:execute_git_clone)
          .with('tcf-workflows', anything, anything)
          .and_return(true)
        allow(repository_manager).to receive(:verify_clone_success).and_return(true)
      end

      it 'handles clone failures gracefully' do
        result = repository_manager.clone_missing_repositories(missing_repos)

        aggregate_failures do
          expect(result['tcf-personas'][:status]).to eq('failed')
          expect(result['tcf-personas'][:error]).to include('Permission denied')
          expect(result['tcf-workflows'][:status]).to eq('cloned')
        end
      end

      it 'continues cloning other repositories after failures' do
        result = repository_manager.clone_missing_repositories(missing_repos)

        expect(result.keys).to contain_exactly('tcf-personas', 'tcf-workflows')
      end
    end

    context 'when no repositories specified' do
      before do
        allow(repository_manager).to receive(:discover_repositories).and_return({
          'tcf-gateway' => { exists: true },
          'tcf-personas' => { exists: false, required: true },
          'tcf-workflows' => { exists: false, required: false }
        })
        allow(repository_manager).to receive(:execute_git_clone).and_return(true)
        allow(repository_manager).to receive(:verify_clone_success).and_return(true)
      end

      it 'clones all missing repositories by default' do
        result = repository_manager.clone_missing_repositories

        aggregate_failures do
          expect(result).to have_key('tcf-personas')
          expect(result).to have_key('tcf-workflows')
          expect(result).not_to have_key('tcf-gateway') # Already exists
        end
      end
    end
  end

  describe '#update_repositories' do
    let(:existing_repos) { ['tcf-gateway', 'tcf-personas'] }

    context 'when updating succeeds' do
      before do
        allow(repository_manager).to receive(:discover_repositories).and_return({
          'tcf-gateway' => { exists: true, path: "#{base_path}/tcf-gateway" },
          'tcf-personas' => { exists: true, path: "#{base_path}/tcf-personas" }
        })
        allow(repository_manager).to receive(:execute_git_pull).and_return(true)
        allow(repository_manager).to receive(:get_latest_commit_info).and_return({
          hash: 'abc123',
          message: 'Latest commit',
          author: 'Developer',
          date: Time.now
        })
      end

      it 'updates all existing repositories' do
        result = repository_manager.update_repositories

        aggregate_failures do
          expect(result).to have_key('tcf-gateway')
          expect(result['tcf-gateway'][:status]).to eq('updated')
          expect(result['tcf-gateway'][:latest_commit]).to include(hash: 'abc123')
        end
      end

      it 'includes commit information in update results' do
        result = repository_manager.update_repositories

        commit_info = result['tcf-gateway'][:latest_commit]
        aggregate_failures do
          expect(commit_info).to include(
            hash: 'abc123',
            message: 'Latest commit',
            author: 'Developer'
          )
          expect(commit_info[:date]).to be_a(Time)
        end
      end
    end

    context 'when updating fails' do
      before do
        allow(repository_manager).to receive(:discover_repositories).and_return({
          'tcf-gateway' => { exists: true, path: "#{base_path}/tcf-gateway" },
          'tcf-personas' => { exists: true, path: "#{base_path}/tcf-personas" }
        })
        allow(repository_manager).to receive(:execute_git_pull)
          .with("#{base_path}/tcf-gateway")
          .and_raise(StandardError, 'Merge conflicts')
        allow(repository_manager).to receive(:execute_git_pull)
          .with("#{base_path}/tcf-personas")
          .and_return(true)
        allow(repository_manager).to receive(:get_latest_commit_info).and_return({
          hash: 'def456', message: 'Working commit', author: 'Developer', date: Time.now
        })
      end

      it 'handles update failures gracefully' do
        result = repository_manager.update_repositories

        aggregate_failures do
          expect(result['tcf-gateway'][:status]).to eq('failed')
          expect(result['tcf-gateway'][:error]).to include('Merge conflicts')
          expect(result['tcf-personas'][:status]).to eq('updated')
        end
      end
    end

    context 'when specific repositories requested' do
      before do
        allow(repository_manager).to receive(:discover_repositories).and_return({
          'tcf-gateway' => { exists: true, path: "#{base_path}/tcf-gateway" },
          'tcf-personas' => { exists: true, path: "#{base_path}/tcf-personas" }
        })
        allow(repository_manager).to receive(:execute_git_pull).and_return(true)
        allow(repository_manager).to receive(:get_latest_commit_info).and_return({
          hash: 'ghi789', message: 'Specific update', author: 'Developer', date: Time.now
        })
      end

      it 'updates only specified repositories' do
        result = repository_manager.update_repositories(['tcf-gateway'])

        aggregate_failures do
          expect(result).to have_key('tcf-gateway')
          expect(result).not_to have_key('tcf-personas')
          expect(result['tcf-gateway'][:status]).to eq('updated')
        end
      end
    end
  end

  describe '#repository_status' do
    before do
      allow(repository_manager).to receive(:discover_repositories).and_return({
        'tcf-gateway' => {
          exists: true,
          path: "#{base_path}/tcf-gateway",
          git_repository: true,
          current_branch: 'master',
          clean: true
        },
        'tcf-personas' => {
          exists: true,
          path: "#{base_path}/tcf-personas",
          git_repository: true,
          current_branch: 'feature/new-feature',
          clean: false
        }
      })
      allow(repository_manager).to receive(:get_latest_commit_info).and_return({
        hash: 'commit123',
        message: 'Latest changes',
        author: 'Dev Team',
        date: Time.now - 3600
      })
    end

    it 'provides comprehensive repository status information' do
      status = repository_manager.repository_status

      aggregate_failures do
        expect(status).to have_key('tcf-gateway')
        expect(status['tcf-gateway']).to include(
          exists: true,
          current_branch: 'master',
          clean: true,
          latest_commit: hash_including(
            hash: 'commit123',
            message: 'Latest changes'
          )
        )
      end
    end

    it 'identifies repositories with uncommitted changes' do
      status = repository_manager.repository_status

      expect(status['tcf-personas'][:clean]).to eq(false)
    end

    it 'shows current branch information' do
      status = repository_manager.repository_status

      aggregate_failures do
        expect(status['tcf-gateway'][:current_branch]).to eq('master')
        expect(status['tcf-personas'][:current_branch]).to eq('feature/new-feature')
      end
    end
  end
end