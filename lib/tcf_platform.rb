# frozen_string_literal: true

require 'pathname'
require 'sinatra'
require 'json'

module TcfPlatform
  VERSION = '1.0.0'

  def self.version
    VERSION
  end

  def self.app
    load_app if @app.nil?
    @app
  end

  def self.root
    @root ||= Pathname.new(__dir__).parent.expand_path
  end

  def self.env
    ENV.fetch('RACK_ENV', 'development')
  end

  def self.load_app
    require_relative '../app'
    require_relative 'service_registry'
    require_relative 'docker_manager'
    require_relative 'config_manager'
    require_relative 'config_generator'
    @app = TcfPlatformApp
  end
end
