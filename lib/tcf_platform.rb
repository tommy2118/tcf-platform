# frozen_string_literal: true

require 'pathname'
require 'sinatra'

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
    @app = TcfPlatformApp
  end
end
