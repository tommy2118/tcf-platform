# frozen_string_literal: true

source 'https://rubygems.org'
ruby '>= 3.2.0', '< 3.5'

# Core web framework
gem 'puma', '~> 6.0'
gem 'rackup'
gem 'sinatra', '~> 4.1'
gem 'sinatra-contrib'

# HTTP client and utilities
gem 'faraday', '~> 2.0'
gem 'faraday-retry'

# Data and caching
gem 'activesupport'
gem 'concurrent-ruby', '~> 1.2'
gem 'redis', '~> 5.0'

# Authentication and security
gem 'bcrypt'
gem 'jwt', '~> 2.7'
gem 'rack-cors'

# Environment and configuration
gem 'dotenv'

# JSON handling
gem 'multi_json'

# CLI tools
gem 'thor', '~> 1.3'

group :development, :test do
  gem 'brakeman' # Static security analysis
  gem 'bundler-audit' # Security vulnerability scanning
  gem 'rack-test'
  gem 'rspec'
  gem 'rspec_junit_formatter' # For CI test reporting
  gem 'rubocop'
  gem 'rubocop-rspec'
  gem 'simplecov' # For test coverage
  gem 'timecop' # For time-based testing
  gem 'webmock'
end

group :development do
  gem 'byebug'
  gem 'rerun'
end
