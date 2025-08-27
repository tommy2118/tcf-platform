require 'rspec'
require 'rack/test'
require 'webmock/rspec'
require 'json'

# Test coverage
if ENV['COVERAGE'] == 'true'
  require 'simplecov'
  SimpleCov.start do
    add_filter '/spec/'
    add_filter '/vendor/'
    add_group 'Controllers', 'app.rb'
    add_group 'Libraries', 'lib'
    minimum_coverage 100
  end
end

# Disable external HTTP connections during tests
WebMock.disable_net_connect!(allow_localhost: true)

# Load environment configuration for tests
ENV['RACK_ENV'] = 'test'
ENV['JWT_SECRET'] = 'test-secret-key'
ENV['REDIS_URL'] = 'redis://localhost:6379/0'

RSpec.configure do |config|
  # Use the new expect syntax
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
    expectations.syntax = :expect
  end

  # Use the new mock syntax
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
    mocks.syntax = :expect
  end

  # Enable shared context metadata behavior
  config.shared_context_metadata_behavior = :apply_to_host_groups

  # Use aggregate_failures for multiple expectations
  config.define_derived_metadata do |meta|
    meta[:aggregate_failures] = true
  end

  # Configure for more strict testing
  config.raise_errors_for_deprecations!
  config.disable_monkey_patching!

  # Include Rack::Test methods in request specs
  config.include Rack::Test::Methods, type: :request

  # Clear test environment before each test
  config.before do
    WebMock.reset!
  end

  # Shared examples and support files
  config.shared_context_metadata_behavior = :apply_to_host_groups
end

# Helper method to parse JSON responses
def json_response
  JSON.parse(last_response.body)
end

# Helper method to make JSON requests
def json_request(verb, path, data = {})
  send(verb, path, data.to_json, { 'CONTENT_TYPE' => 'application/json' })
end

# Helper method to capture stdout for CLI testing
def capture_stdout
  old_stdout = $stdout
  $stdout = StringIO.new
  yield
  $stdout.string
ensure
  $stdout = old_stdout
end

# Require support files
Dir[File.join(__dir__, 'support', '**', '*.rb')].each { |f| require f }

# Helper method to check CORS headers
def expect_cors_headers
  expect(last_response.headers).to include(
    'Access-Control-Allow-Origin' => '*',
    'Access-Control-Allow-Methods' => 'GET, POST, PUT, DELETE, OPTIONS',
    'Access-Control-Allow-Headers' => 'Content-Type, Authorization'
  )
end