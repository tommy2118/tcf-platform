source 'https://rubygems.org'
ruby '>= 3.2.0', '< 3.5'

# Core web framework
gem 'sinatra', '~> 4.1'
gem 'sinatra-contrib'
gem 'puma', '~> 6.0'
gem 'rackup'

# HTTP client and utilities
gem 'faraday', '~> 2.0'
gem 'faraday-retry'

# Data and caching
gem 'redis', '~> 5.0'
gem 'activesupport'
gem 'concurrent-ruby', '~> 1.2'

# Authentication and security
gem 'jwt', '~> 2.7'
gem 'rack-cors'
gem 'bcrypt'

# Environment and configuration
gem 'dotenv'

# JSON handling
gem 'multi_json'

# CLI tools
gem 'thor', '~> 1.3'

group :development, :test do
  gem 'rspec'
  gem 'rack-test'
  gem 'webmock'
  gem 'timecop' # For time-based testing
  gem 'rubocop'
  gem 'rubocop-rspec'
  gem 'rspec_junit_formatter' # For CI test reporting
  gem 'simplecov' # For test coverage
  gem 'bundler-audit' # Security vulnerability scanning
  gem 'brakeman' # Static security analysis
end

group :development do
  gem 'rerun'
  gem 'byebug'
end