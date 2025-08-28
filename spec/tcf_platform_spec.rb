# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe TcfPlatform do
  describe '.version' do
    it 'returns the current version' do
      expect(TcfPlatform.version).to match(/\d+\.\d+\.\d+/)
    end
  end

  describe '.app' do
    it 'returns a Sinatra application' do
      expect(TcfPlatform.app).to be < Sinatra::Base
    end
  end

  describe '.root' do
    it 'returns the root path of the application' do
      expect(TcfPlatform.root).to be_a(Pathname)
      expect(TcfPlatform.root.to_s).to end_with('tcf-platform')
    end
  end

  describe '.env' do
    it 'returns the current environment' do
      original_env = ENV.fetch('RACK_ENV', nil)
      ENV['RACK_ENV'] = 'test'
      expect(TcfPlatform.env).to eq('test')
    ensure
      ENV['RACK_ENV'] = original_env
    end
  end
end
