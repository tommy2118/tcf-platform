require 'sinatra/base'
require 'sinatra/json'
require 'json'
require 'dotenv/load'
require 'securerandom'

class TcfPlatformApp < Sinatra::Base
  configure do
    set :port, ENV.fetch('PORT', 3000).to_i
    set :bind, ENV.fetch('BIND_HOST', '0.0.0.0')
    set :public_folder, 'public'
    set :logging, true
  end

  # Security headers
  before do
    response.headers['X-Content-Type-Options'] = 'nosniff'
    response.headers['X-Frame-Options'] = 'DENY'
    response.headers['X-XSS-Protection'] = '1; mode=block'
    response.headers['Referrer-Policy'] = 'strict-origin-when-cross-origin'
    
    # CORS headers
    response.headers['Access-Control-Allow-Origin'] = '*'
    response.headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS'
    response.headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization'
    response.headers['Access-Control-Allow-Credentials'] = 'true'
  end

  # Health check endpoint
  get '/health' do
    content_type :json
    json({
      status: 'healthy',
      timestamp: Time.now.iso8601,
      version: ENV.fetch('APP_VERSION', '1.0.0'),
      environment: ENV.fetch('RACK_ENV', 'development'),
      service: 'tcf-platform'
    })
  end

  # 404 handler
  not_found do
    content_type :json
    json({
      error: 'not_found',
      message: 'The requested endpoint not found.',
      status: 404,
      timestamp: Time.now.iso8601
    })
  end

  # Global error handler
  error StandardError do
    error = env['sinatra.error']
    status 500
    content_type :json

    error_response = {
      error: 'internal_server_error',
      message: ENV['RACK_ENV'] == 'production' ? 
        'An internal error occurred' : 
        'An internal error occurred while processing your request.',
      status: 500,
      timestamp: Time.now.iso8601,
      error_id: SecureRandom.uuid
    }

    # Include details in development
    error_response[:details] = error.message if ENV['RACK_ENV'] == 'development'

    json error_response
  end

  # CORS preflight handler
  options '*' do
    response.headers['Access-Control-Allow-Origin'] = '*'
    response.headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS'
    response.headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization'
    response.headers['Access-Control-Max-Age'] = '86400'
    response.headers['Allow'] = 'GET, POST, PUT, DELETE, OPTIONS'
    200
  end
end