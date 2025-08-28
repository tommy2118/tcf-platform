# frozen_string_literal: true

require 'spec_helper'
require 'tcf_platform'
require_relative '../../lib/cli/platform_cli'

RSpec.describe TcfPlatform::CLI do
  subject(:cli) { described_class.new }

  # Helper method to capture stdout
  def capture_stdout(&block)
    original_stdout = $stdout
    $stdout = fake = StringIO.new
    begin
      yield
    ensure
      $stdout = original_stdout
    end
    fake.string
  end

  describe '#up' do
    it 'starts all services' do
      expect(capture_stdout { cli.up }).to include('Starting TCF Platform services...')
    end

    it 'starts specific services when specified' do
      expect(capture_stdout { cli.up('gateway') }).to include('Starting tcf-gateway')
    end

    it 'shows success message when services start' do
      output = capture_stdout { cli.up }
      expect(output).to include('✅')
    end
  end

  describe '#down' do
    it 'stops all services gracefully' do
      expect(capture_stdout { cli.down }).to include('Stopping TCF Platform services...')
    end

    it 'shows success message when services stop' do
      output = capture_stdout { cli.down }
      expect(output).to include('✅')
    end
  end

  describe '#status' do
    it 'shows comprehensive service status' do
      output = capture_stdout { cli.status }
      expect(output).to include('Service Status', 'tcf-gateway', 'Health')
    end

    it 'displays port information for services' do
      output = capture_stdout { cli.status }
      expect(output).to include('Port', '3000')
    end
  end

  describe '#restart' do
    it 'restarts all services when none specified' do
      expect(capture_stdout { cli.restart }).to include('Restarting TCF Platform services...')
    end

    it 'restarts specific services when specified' do
      expect(capture_stdout { cli.restart('gateway') }).to include('Restarting tcf-gateway')
    end
  end
end