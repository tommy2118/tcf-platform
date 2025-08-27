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
      expect(TcfPlatform.env).to eq('test')
    end
  end
end