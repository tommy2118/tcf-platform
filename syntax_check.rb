#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple script to check if files can be loaded without syntax errors

require 'English'
files_to_check = [
  'lib/config_validator.rb',
  'lib/security_manager.rb',
  'lib/cli/config_help_commands.rb',
  'lib/cli/config_generation_commands.rb',
  'lib/cli/config_validation_commands.rb',
  'lib/cli/config_display_commands.rb',
  'lib/cli/config_management_commands.rb',
  'lib/cli/config_commands.rb'
]

puts 'Checking syntax for refactored files...'

files_to_check.each do |file|
  print "Checking #{file}... "
  system("ruby -c #{file}")
  if $CHILD_STATUS.success?
    puts 'OK'
  else
    puts 'FAILED'
  end
end

puts 'Syntax check complete!'
