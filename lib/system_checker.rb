# frozen_string_literal: true

require 'open3'
require 'socket'

module TcfPlatform
  # System Prerequisites Validation
  # Validates that all required system components are available for TCF development
  class SystemChecker
    REQUIRED_COMMANDS = %w[docker docker-compose git].freeze
    TCF_PORTS = [3000, 3001, 3002, 3003, 3004, 3005, 5432, 6379, 6333].freeze

    def docker_available?
      command_available?('docker') && docker_daemon_running?
    end

    def docker_compose_available?
      command_available?('docker-compose') || command_available?('docker') && docker_compose_v2_available?
    end

    def git_available?
      command_available?('git')
    end

    def prerequisites_met?
      checks = []
      all_met = true

      # Check Docker
      docker_check = check_docker_prerequisite
      checks << docker_check
      all_met = false unless docker_check[:status] == 'pass'

      # Check Git
      git_check = check_git_prerequisite
      checks << git_check
      all_met = false unless git_check[:status] == 'pass'

      # Check ports
      ports_check = check_required_ports
      checks << ports_check
      all_met = false unless ports_check[:status] == 'pass'

      # Check disk space
      disk_check = check_disk_space
      checks << disk_check
      all_met = false unless disk_check[:status] == 'pass'

      # Check memory
      memory_check = check_memory
      checks << memory_check
      all_met = false unless memory_check[:status] == 'pass'

      {
        met: all_met,
        checks: checks
      }
    end

    def check_ports(ports = TCF_PORTS)
      blocked_ports = []
      available_ports = []

      ports.each do |port|
        if port_in_use?(port)
          blocked_ports << port
        else
          available_ports << port
        end
      end

      {
        available: blocked_ports.empty?,
        blocked_ports: blocked_ports,
        available_ports: available_ports,
        total_checked: ports.size
      }
    end

    private

    def command_available?(command)
      _stdout, _stderr, status = Open3.capture3("which #{command}")
      status.success?
    rescue StandardError
      false
    end

    def docker_daemon_running?
      _stdout, _stderr, status = Open3.capture3('docker info')
      status.success?
    rescue StandardError
      false
    end

    def docker_compose_v2_available?
      _stdout, _stderr, status = Open3.capture3('docker compose version')
      status.success?
    rescue StandardError
      false
    end

    def port_in_use?(port)
      TCPServer.open('127.0.0.1', port) do |_server|
        false
      end
    rescue Errno::EADDRINUSE
      true
    rescue StandardError
      false
    end

    def check_docker_prerequisite
      if docker_available? && docker_compose_available?
        { name: 'docker', status: 'pass', message: 'Docker and Docker Compose available' }
      elsif docker_available?
        { name: 'docker', status: 'warning', message: 'Docker available but Docker Compose missing' }
      else
        { name: 'docker', status: 'fail', message: 'Docker not available or daemon not running' }
      end
    end

    def check_git_prerequisite
      if git_available?
        { name: 'git', status: 'pass', message: 'Git available' }
      else
        { name: 'git', status: 'fail', message: 'Git not available' }
      end
    end

    def check_required_ports
      ports_result = check_ports
      critical_blocked = ports_result[:blocked_ports] & [3000, 5432, 6379]
      
      if critical_blocked.empty?
        { name: 'ports', status: 'pass', message: "All critical ports available (#{ports_result[:available_ports].size} total)" }
      elsif critical_blocked.size < 2
        { name: 'ports', status: 'warning', message: "Some ports in use: #{critical_blocked.join(', ')}" }
      else
        { name: 'ports', status: 'fail', message: "Critical ports blocked: #{critical_blocked.join(', ')}" }
      end
    end

    def check_disk_space
      # Check available disk space (simplified check)
      available_mb = disk_space_available
      
      if available_mb > 2048  # 2GB minimum
        { name: 'disk_space', status: 'pass', message: "#{available_mb}MB available" }
      elsif available_mb > 1024  # 1GB warning
        { name: 'disk_space', status: 'warning', message: "Low disk space: #{available_mb}MB available" }
      else
        { name: 'disk_space', status: 'fail', message: "Insufficient disk space: #{available_mb}MB available" }
      end
    end

    def check_memory
      # Check available memory (simplified)
      available_mb = memory_available
      
      if available_mb > 4096  # 4GB recommended
        { name: 'memory', status: 'pass', message: "#{available_mb}MB RAM available" }
      elsif available_mb > 2048  # 2GB minimum
        { name: 'memory', status: 'warning', message: "Limited RAM: #{available_mb}MB available" }
      else
        { name: 'memory', status: 'fail', message: "Insufficient RAM: #{available_mb}MB available" }
      end
    end

    def disk_space_available
      # Use df command to check disk space
      stdout, _stderr, status = Open3.capture3('df -m .')
      return 0 unless status.success?

      lines = stdout.split("\n")
      return 0 if lines.size < 2

      # Parse df output: Filesystem 1M-blocks Used Available Use% Mounted
      parts = lines[1].split
      return 0 if parts.size < 4

      parts[3].to_i  # Available space in MB
    rescue StandardError
      0
    end

    def memory_available
      case RUBY_PLATFORM
      when /darwin/
        # macOS
        parse_memory_darwin
      when /linux/
        # Linux
        parse_memory_linux
      else
        4096  # Default assumption
      end
    end

    def parse_memory_darwin
      # Use vm_stat on macOS
      stdout, _stderr, status = Open3.capture3('vm_stat')
      return 4096 unless status.success?

      # Parse vm_stat output
      free_pages = stdout.match(/Pages free:\s+(\d+)/)&.captures&.first&.to_i || 0
      page_size = 4096  # 4KB page size on macOS
      
      (free_pages * page_size) / 1024 / 1024  # Convert to MB
    rescue StandardError
      4096
    end

    def parse_memory_linux
      # Use /proc/meminfo on Linux
      return 4096 unless File.exist?('/proc/meminfo')

      meminfo = File.read('/proc/meminfo')
      available = meminfo.match(/MemAvailable:\s+(\d+) kB/)&.captures&.first&.to_i || 0
      
      available / 1024  # Convert KB to MB
    rescue StandardError
      4096
    end
  end
end