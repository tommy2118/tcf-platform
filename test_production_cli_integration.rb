#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script to verify production CLI integration
require_relative 'lib/cli/platform_cli'

puts "🧪 Testing Production CLI Integration"
puts "=" * 50

begin
  # Test CLI initialization with production commands
  cli = TcfPlatform::CLI.new
  puts "✅ CLI initialized successfully with production commands"

  # Test that production commands are included
  included_modules = TcfPlatform::CLI.included_modules
  production_included = included_modules.any? { |mod| mod.to_s.include?('ProductionCommands') }
  
  if production_included
    puts "✅ ProductionCommands module included in CLI"
  else
    puts "❌ ProductionCommands module not found in CLI"
  end

  # Test help output includes production commands
  puts ""
  puts "📋 Testing help output for production commands..."
  
  # Capture help output
  help_output = `ruby -e "require_relative 'lib/cli/platform_cli'; TcfPlatform::CLI.new.help" 2>/dev/null`
  
  production_commands = [
    'tcf-platform prod deploy VERSION',
    'tcf-platform prod rollback',
    'tcf-platform prod status', 
    'tcf-platform prod audit',
    'tcf-platform prod validate',
    'tcf-platform prod monitor'
  ]

  all_commands_found = true
  production_commands.each do |command|
    if help_output.include?(command)
      puts "✅ Help includes: #{command}"
    else
      puts "❌ Help missing: #{command}"
      all_commands_found = false
    end
  end

  if all_commands_found
    puts ""
    puts "✅ ALL PRODUCTION CLI INTEGRATION TESTS PASSED"
    puts "🚀 Production deployment system ready for use"
  else
    puts ""
    puts "❌ Some production CLI integration issues detected"
  end

rescue StandardError => e
  puts "❌ CLI integration test failed: #{e.message}"
  puts "   #{e.backtrace.first}"
end

puts ""
puts "🔚 Production CLI integration test complete"