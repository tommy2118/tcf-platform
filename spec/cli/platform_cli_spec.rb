require_relative '../spec_helper'
require 'stringio'

RSpec.describe TcfPlatform::CLI do
  let(:cli) { described_class.new }

  describe '#help' do
    it 'displays available commands' do
      output = capture_stdout { cli.help }
      
      aggregate_failures do
        expect(output).to include('tcf-platform commands:')
        expect(output).to include('help')
        expect(output).to include('version')
        expect(output).to include('server')
        expect(output).to include('status')
      end
    end
  end

  describe '#version' do
    it 'displays the version' do
      output = capture_stdout { cli.version }
      expect(output).to include(TcfPlatform.version)
    end
  end

  describe '#server' do
    it 'displays server start message with default port' do
      allow(cli).to receive(:exec)
      
      output = capture_stdout { cli.server }
      
      aggregate_failures do
        expect(output).to include('Starting TCF Platform server')
        expect(output).to include('port 3000')
      end
    end

    it 'accepts port option' do
      allow(cli).to receive(:exec)
      
      cli.options = { 'port' => '4000' }
      output = capture_stdout { cli.server }
      
      expect(output).to include('port 4000')
    end

    it 'accepts environment option' do
      allow(cli).to receive(:exec)
      
      cli.options = { 'environment' => 'production' }
      output = capture_stdout { cli.server }
      
      expect(output).to include('environment: production')
    end
  end

  describe '#status' do
    it 'displays application status' do
      output = capture_stdout { cli.status }
      
      aggregate_failures do
        expect(output).to include('TCF Platform Status')
        expect(output).to include("Version: #{TcfPlatform.version}")
        expect(output).to include("Environment: #{TcfPlatform.env}")
        expect(output).to include("Root: #{TcfPlatform.root}")
      end
    end
  end
end