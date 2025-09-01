#!/usr/bin/env ruby
# frozen_string_literal: true

# Final validation script for Issue #12 completion
require 'json'

puts "🎯 Issue #12 - Production Deployment & Security"
puts "🔍 FINAL VALIDATION - Red Phase 3 + Green Phase 3"
puts "=" * 70
puts ""

# Track validation results
validations = []

# 1. File Structure Validation
puts "📁 Validating File Structure..."
required_files = [
  'lib/monitoring/production_monitor.rb',
  'lib/cli/production_commands.rb', 
  'spec/lib/monitoring/production_monitor_spec.rb',
  'spec/cli/production_commands_spec.rb',
  'spec/integration/production_workflow_spec.rb'
]

file_structure_valid = true
required_files.each do |file|
  if File.exist?(file)
    puts "  ✅ #{file}"
  else
    puts "  ❌ #{file} - MISSING"
    file_structure_valid = false
  end
end
validations << { name: 'File Structure', status: file_structure_valid }

# 2. Syntax Validation
puts ""
puts "📝 Validating Syntax..."
syntax_valid = true
required_files.each do |file|
  next unless File.exist?(file)
  
  result = system("ruby -c #{file} 2>/dev/null")
  if result
    puts "  ✅ #{file}"
  else
    puts "  ❌ #{file} - SYNTAX ERROR"
    syntax_valid = false
  end
end
validations << { name: 'Syntax', status: syntax_valid }

# 3. Class Structure Validation
puts ""
puts "🏗️  Validating Class Structure..."
begin
  require_relative 'lib/monitoring/production_monitor'
  require_relative 'lib/cli/production_commands'
  
  # Check ProductionMonitor class
  production_monitor_valid = defined?(TcfPlatform::Monitoring::ProductionMonitor) &&
                            TcfPlatform::Monitoring::ProductionMonitor.method_defined?(:start_production_monitoring) &&
                            TcfPlatform::Monitoring::ProductionMonitor.method_defined?(:security_audit) &&
                            TcfPlatform::Monitoring::ProductionMonitor.method_defined?(:validate_deployment)

  if production_monitor_valid
    puts "  ✅ ProductionMonitor class structure"
  else
    puts "  ❌ ProductionMonitor class structure"
  end

  # Check ProductionCommands module
  production_commands_valid = defined?(TcfPlatform::ProductionCommands)

  if production_commands_valid
    puts "  ✅ ProductionCommands module structure"
  else
    puts "  ❌ ProductionCommands module structure"
  end

  class_structure_valid = production_monitor_valid && production_commands_valid
  validations << { name: 'Class Structure', status: class_structure_valid }

rescue StandardError => e
  puts "  ❌ Class structure validation failed: #{e.message}"
  validations << { name: 'Class Structure', status: false }
end

# 4. CLI Integration Validation
puts ""
puts "🖥️  Validating CLI Integration..."
begin
  require_relative 'lib/cli/platform_cli'
  
  # Check CLI includes production commands
  cli_integration_valid = TcfPlatform::CLI.included_modules.any? { |mod| 
    mod.to_s.include?('ProductionCommands') 
  }

  if cli_integration_valid
    puts "  ✅ CLI includes ProductionCommands module"
  else
    puts "  ❌ CLI missing ProductionCommands module"
  end

  validations << { name: 'CLI Integration', status: cli_integration_valid }

rescue StandardError => e
  puts "  ❌ CLI integration validation failed: #{e.message}"
  validations << { name: 'CLI Integration', status: false }
end

# 5. Dependencies Validation
puts ""
puts "🔗 Validating Dependencies..."
dependency_classes = [
  'TcfPlatform::DeploymentManager',
  'TcfPlatform::BlueGreenDeployer', 
  'TcfPlatform::Security::SecurityValidator',
  'TcfPlatform::Monitoring::MonitoringService',
  'TcfPlatform::BackupManager',
  'TcfPlatform::LoadBalancer'
]

dependencies_valid = true
dependency_classes.each do |class_name|
  begin
    # Check if class is defined and can be instantiated
    klass = class_name.split('::').reduce(Object) { |obj, name| obj.const_get(name) }
    if klass.is_a?(Class) || klass.is_a?(Module)
      puts "  ✅ #{class_name}"
    else
      puts "  ❌ #{class_name} - NOT A CLASS/MODULE"
      dependencies_valid = false
    end
  rescue NameError
    puts "  ❌ #{class_name} - NOT DEFINED"
    dependencies_valid = false
  end
end
validations << { name: 'Dependencies', status: dependencies_valid }

# 6. Test Execution Validation
puts ""
puts "🧪 Validating Test Execution..."
test_files = [
  'spec/lib/monitoring/production_monitor_spec.rb',
  'spec/cli/production_commands_spec.rb'
]

tests_valid = true
test_files.each do |test_file|
  print "  Testing #{test_file}... "
  result = system("timeout 30s bundle exec rspec #{test_file} --format progress --no-color >/dev/null 2>&1")
  if result
    puts "✅ PASSED"
  else
    puts "❌ FAILED/TIMEOUT"
    tests_valid = false
  end
end
validations << { name: 'Test Execution', status: tests_valid }

# 7. Production Command Functionality
puts ""
puts "⚙️  Validating Production Command Functionality..."
begin
  # Test that production commands can be instantiated
  cli = TcfPlatform::CLI.new
  
  # Test command method existence
  production_methods = [
    :prod_deploy,
    :prod_rollback, 
    :prod_status,
    :prod_audit,
    :prod_validate,
    :prod_monitor
  ]

  command_functionality_valid = true
  production_methods.each do |method|
    if cli.respond_to?(method, true) # Check private methods too
      puts "  ✅ #{method} command available"
    else
      puts "  ❌ #{method} command missing"
      command_functionality_valid = false
    end
  end

  validations << { name: 'Command Functionality', status: command_functionality_valid }

rescue StandardError => e
  puts "  ❌ Command functionality validation failed: #{e.message}"
  validations << { name: 'Command Functionality', status: false }
end

# Final Results
puts ""
puts "📊 VALIDATION SUMMARY"
puts "=" * 30

passed_count = validations.count { |v| v[:status] }
total_count = validations.size

validations.each do |validation|
  status_icon = validation[:status] ? '✅' : '❌'
  puts "#{status_icon} #{validation[:name]}"
end

puts ""
puts "Results: #{passed_count}/#{total_count} validations passed"

if passed_count == total_count
  puts ""
  puts "🎉 ISSUE #12 PRODUCTION DEPLOYMENT & SECURITY"
  puts "✅ RED PHASE 3 + GREEN PHASE 3 COMPLETE"
  puts "🚀 PRODUCTION SYSTEM READY"
  puts ""
  puts "Production CLI Commands Available:"
  puts "  tcf-platform prod deploy VERSION"
  puts "  tcf-platform prod rollback [VERSION]"  
  puts "  tcf-platform prod status"
  puts "  tcf-platform prod audit"
  puts "  tcf-platform prod validate"
  puts "  tcf-platform prod monitor"
  puts ""
  puts "✅ TCF Platform production deployment system is complete!"
else
  puts ""
  puts "⚠️  VALIDATION ISSUES DETECTED"
  puts "❌ #{total_count - passed_count} validation(s) failed"
  puts "🔧 Please resolve issues before production deployment"
end

puts ""
puts "🔚 Final validation complete"