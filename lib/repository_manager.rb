# frozen_string_literal: true

require 'fileutils'

module TcfPlatform
  # Manages repository operations for TCF Platform services
  class RepositoryManager
    def initialize(config_manager, base_path = '/Users/tcaruso/src')
      @config_manager = config_manager
      @base_path = base_path
    end

    def discover_repositories
      repositories = {}

      @config_manager.repository_config.each do |repo_name, repo_config|
        repo_path = File.join(@base_path, repo_name)

        repositories[repo_name] = {
          path: repo_path,
          url: repo_config['url'],
          branch: repo_config['branch'],
          required: repo_config['required'],
          exists: Dir.exist?(repo_path),
          git_repository: git_repository?(repo_path),
          current_branch: exists_and_git?(repo_path) ? get_current_branch(repo_path) : nil,
          clean: exists_and_git?(repo_path) ? working_directory_clean?(repo_path) : nil
        }
      end

      repositories
    end

    def clone_missing_repositories(repo_names = nil)
      target_repos = if repo_names
                       repo_names
                     else
                       missing_repositories = discover_repositories.reject { |_, info| info[:exists] }
                       missing_repositories.keys
                     end

      results = {}

      target_repos.each do |repo_name|
        repo_config = @config_manager.repository_config[repo_name]
        next unless repo_config

        repo_path = File.join(@base_path, repo_name)

        begin
          execute_git_clone(repo_name, repo_config['url'], repo_path)

          results[repo_name] = if verify_clone_success(repo_path)
                                 {
                                   status: 'cloned',
                                   path: repo_path,
                                   url: repo_config['url']
                                 }
                               else
                                 {
                                   status: 'failed',
                                   path: repo_path,
                                   error: 'Clone verification failed'
                                 }
                               end
        rescue StandardError => e
          results[repo_name] = {
            status: 'failed',
            path: repo_path,
            error: e.message
          }
        end
      end

      results
    end

    def update_repositories(repo_names = nil)
      discovered_repos = discover_repositories
      target_repos = repo_names || discovered_repos.select { |_, info| info[:exists] }.keys

      results = {}

      target_repos.each do |repo_name|
        repo_info = discovered_repos[repo_name]
        next unless repo_info && repo_info[:exists]

        repo_path = repo_info[:path]

        begin
          execute_git_pull(repo_path)
          latest_commit = get_latest_commit_info(repo_path)

          results[repo_name] = {
            status: 'updated',
            path: repo_path,
            latest_commit: latest_commit
          }
        rescue StandardError => e
          results[repo_name] = {
            status: 'failed',
            path: repo_path,
            error: e.message
          }
        end
      end

      results
    end

    def repository_status
      repositories = discover_repositories

      repositories.each_value do |repo_info|
        next unless repo_info[:exists] && repo_info[:git_repository]

        repo_info[:latest_commit] = get_latest_commit_info(repo_info[:path])
      end

      repositories
    end

    def ensure_all_repositories
      missing = discover_repositories.select { |_, info| !info[:exists] }
      return true if missing.empty?
      
      results = clone_missing_repositories(missing.keys)
      failed = results.select { |_, result| result[:status] == 'failed' }
      
      raise StandardError, "Failed to clone repositories: #{failed.keys.join(', ')}" unless failed.empty?
      
      true
    end

    private

    def git_repository?(path)
      return false unless Dir.exist?(path)

      File.exist?(File.join(path, '.git'))
    end

    def exists_and_git?(path)
      Dir.exist?(path) && git_repository?(path)
    end

    def get_current_branch(repo_path)
      Dir.chdir(repo_path) do
        `git branch --show-current`.strip
      end
    rescue StandardError
      'unknown'
    end

    def working_directory_clean?(repo_path)
      Dir.chdir(repo_path) do
        status_output = `git status --porcelain`.strip
        status_output.empty?
      end
    rescue StandardError
      false
    end

    def execute_git_clone(repo_name, repo_url, target_path)
      # Ensure parent directory exists
      FileUtils.mkdir_p(File.dirname(target_path))

      # Remove target directory if it exists but is not a git repository
      FileUtils.rm_rf(target_path) if Dir.exist?(target_path) && !git_repository?(target_path)

      # Clone the repository
      unless system("git clone #{repo_url} #{target_path}", out: File::NULL, err: File::NULL)
        raise StandardError, "Failed to clone #{repo_name} from #{repo_url}"
      end

      true
    end

    def verify_clone_success(repo_path)
      Dir.exist?(repo_path) && git_repository?(repo_path)
    end

    def execute_git_pull(repo_path)
      Dir.chdir(repo_path) do
        raise StandardError, 'Failed to pull latest changes' unless system('git pull', out: File::NULL, err: File::NULL)
      end

      true
    end

    def get_latest_commit_info(repo_path)
      Dir.chdir(repo_path) do
        commit_hash = `git rev-parse HEAD`.strip
        commit_message = `git log -1 --pretty=format:"%s"`.strip
        commit_author = `git log -1 --pretty=format:"%an"`.strip
        commit_date_str = `git log -1 --pretty=format:"%ci"`.strip

        {
          hash: commit_hash,
          message: commit_message,
          author: commit_author,
          date: Time.parse(commit_date_str)
        }
      end
    rescue StandardError => e
      {
        hash: 'unknown',
        message: 'Unable to retrieve commit info',
        author: 'unknown',
        date: Time.now,
        error: e.message
      }
    end
  end
end
