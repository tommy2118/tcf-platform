# frozen_string_literal: true

require_relative 'config_manager'

module TcfPlatform
  class BuildCoordinator
    def initialize(repository_manager, config_manager)
      @repository_manager = repository_manager
      @config_manager = config_manager
    end

    def analyze_dependencies
      dependencies = @config_manager.build_dependencies.dup
      detect_circular_dependencies(dependencies)
      dependencies
    end

    def calculate_build_order(requested_services = nil)
      dependencies = analyze_dependencies

      # If specific services requested, include their dependencies
      if requested_services
        all_needed_services = Set.new
        requested_services.each do |service|
          collect_dependencies(service, dependencies, all_needed_services)
        end

        # Filter dependencies to only include needed services
        filtered_deps = dependencies.slice(*all_needed_services)
        return topological_sort(filtered_deps)
      end

      topological_sort(dependencies)
    end

    def build_services(services_to_build)
      build_order = calculate_build_order(services_to_build)
      results = {}
      failed_services = Set.new
      repo_status = @repository_manager.repository_status

      build_order.each do |service_name|
        # Skip if repository doesn't exist
        service_repo_info = repo_status[service_name]
        unless service_repo_info && service_repo_info[:exists]
          results[service_name] = {
            status: 'skipped',
            reason: 'repository not found'
          }
          next
        end

        # Skip if any dependency failed
        service_deps = @config_manager.build_dependencies[service_name] || []
        if service_deps.any? { |dep| failed_services.include?(dep) }
          results[service_name] = {
            status: 'skipped',
            reason: 'dependency failed'
          }
          next
        end

        # Build the service
        begin
          build_result = build_single_service(service_name)
          results[service_name] = build_result

          failed_services << service_name if build_result[:status] == 'failed'
        rescue StandardError => e
          results[service_name] = {
            status: 'failed',
            error: e.message
          }
          failed_services << service_name
        end
      end

      results
    end

    def parallel_build(services)
      results = {}

      threads = services.map do |service_name|
        Thread.new do
          build_result = build_single_service(service_name)
          results[service_name] = build_result
        rescue StandardError => e
          results[service_name] = {
            status: 'failed',
            error: e.message
          }
        end
      end

      threads.each(&:join)
      results
    end

    def build_status
      docker_images_data = docker_images
      all_services = @config_manager.build_dependencies.keys
      status = {}

      all_services.each do |service_name|
        if docker_images_data.key?(service_name)
          image_info = docker_images_data[service_name]
          age_hours = (Time.now - image_info[:created]) / 3600.0

          status[service_name] = {
            status: 'built',
            image_id: image_info[:image_id],
            created: image_info[:created],
            size_mb: image_info[:size_mb],
            age_hours: age_hours
          }
        else
          status[service_name] = {
            status: 'not_built',
            image_id: nil,
            created: nil,
            size_mb: nil,
            age_hours: nil
          }
        end
      end

      status
    end

    private

    def detect_circular_dependencies(dependencies)
      # Use DFS to detect cycles
      visited = Set.new
      rec_stack = Set.new

      dependencies.each_key do |service|
        next if visited.include?(service)

        next unless cycle?(service, dependencies, visited, rec_stack)

        # Find the actual cycle for error reporting
        cycle = find_cycle(service, dependencies)
        raise CircularDependencyError, "Circular dependency detected: #{cycle.join(' -> ')}"
      end
    end

    def cycle?(service, dependencies, visited, rec_stack)
      visited << service
      rec_stack << service

      deps = dependencies[service] || []
      deps.each do |dep|
        if !visited.include?(dep)
          return true if cycle?(dep, dependencies, visited, rec_stack)
        elsif rec_stack.include?(dep)
          return true
        end
      end

      rec_stack.delete(service)
      false
    end

    def find_cycle(start_service, dependencies)
      # Simple cycle detection for error reporting
      path = []
      visited = Set.new

      current = start_service
      while current && !visited.include?(current)
        path << current
        visited << current
        deps = dependencies[current] || []
        current = deps.first
      end

      if current
        cycle_start_index = path.index(current)
        return path[cycle_start_index..] + [current] if cycle_start_index
      end

      path
    end

    def collect_dependencies(service, dependencies, collected)
      return if collected.include?(service)

      collected << service
      deps = dependencies[service] || []
      deps.each do |dep|
        collect_dependencies(dep, dependencies, collected)
      end
    end

    def topological_sort(dependencies)
      # Kahn's algorithm for topological sorting
      # Note: Our dependencies hash is service -> [dependencies], but we need to build dependencies first
      in_degree = Hash.new(0)
      graph = Hash.new { |h, k| h[k] = [] }

      # Initialize all services
      dependencies.each_key { |service| in_degree[service] = 0 }

      # Build reverse graph and calculate in-degrees
      # If A depends on B, then B must be built before A
      dependencies.each do |service, deps|
        deps.each do |dep|
          graph[dep] << service # dep -> service (dep must come before service)
          in_degree[service] += 1
        end
      end

      # Find services with no dependencies (in-degree = 0)
      queue = []
      in_degree.each do |service, degree|
        queue << service if degree.zero?
      end

      result = []

      until queue.empty?
        current = queue.shift
        result << current

        # For each service that depends on current
        graph[current].each do |dependent|
          in_degree[dependent] -= 1
          queue << dependent if in_degree[dependent].zero?
        end
      end

      result
    end

    def build_single_service(service_name)
      # This would normally run docker build commands
      # For now, return a mock successful result
      {
        status: 'success',
        image_id: "sha256:#{service_name}",
        build_time: 30.0,
        size_mb: 100.0
      }
    end

    def docker_images
      # This would normally query docker images
      # For now, return mock data
      {}
    end
  end
end
