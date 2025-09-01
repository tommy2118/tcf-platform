#!/usr/bin/env ruby
# frozen_string_literal: true

# Quick test to verify Red Phase 3 - should show failing tests

puts "🔴 Testing Red Phase 3 - Production CLI & Monitoring"
puts "=" * 60
puts ""

# Test file syntax first
production_files = [
  'lib/monitoring/production_monitor.rb',
  'lib/cli/production_commands.rb',
  'spec/lib/monitoring/production_monitor_spec.rb',
  'spec/cli/production_commands_spec.rb',
  'spec/integration/production_workflow_spec.rb'
]

puts "📋 Checking syntax for new files..."
syntax_ok = true

production_files.each do |file|
  print "  #{file}... "
  result = system("ruby -c #{file} 2>/dev/null")
  if result
    puts "✅ OK"
  else
    puts "❌ SYNTAX ERROR"
    syntax_ok = false
  end
end

puts ""

if syntax_ok
  puts "✅ All syntax checks passed"
  puts ""
  puts "🧪 Running production monitor tests..."
  system("bundle exec rspec spec/lib/monitoring/production_monitor_spec.rb -f documentation")
  
  puts ""
  puts "🧪 Running production CLI tests..."  
  system("bundle exec rspec spec/cli/production_commands_spec.rb -f documentation")
else
  puts "❌ Syntax errors detected. Fix syntax before running tests."
end

puts ""
puts "🔴 Red Phase 3 test complete - expect failures for unimplemented features"