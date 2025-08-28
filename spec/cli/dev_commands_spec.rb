# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/cli/platform_cli'

RSpec.describe 'TcfPlatform::CLI Development Commands' do
  let(:cli) { TcfPlatform::CLI.new }

  describe '#dev_setup' do
    it 'has dev setup command available' do
      expect(cli).to respond_to(:dev_setup)
    end

    it 'orchestrates complete development environment setup' do
      output = capture_stdout do
        cli.dev_setup
      end

      aggregate_failures do
        expect(output).to include('Setting up TCF development environment')
        expect(output).to match(/Prerequisites|Docker|Repository/)
      end
    end

    it 'supports verbose output mode' do
      output = capture_stdout do
        cli.invoke(:dev_setup, [], { verbose: true })
      end

      aggregate_failures do
        expect(output).to include('Setting up TCF development environment')
        expect(output.length).to be > 100  # Verbose should produce more output
      end
    end

    it 'handles setup failures gracefully' do
      # This test should pass even if prerequisites aren't met
      output = capture_stdout do
        cli.dev_setup
      end

      aggregate_failures do
        expect(output).to be_a(String)
        expect(output).not_to be_empty
      end
    end
  end

  describe '#dev_test' do
    it 'has dev test command available' do
      expect(cli).to respond_to(:dev_test)
    end

    it 'coordinates test execution across all services' do
      output = capture_stdout do
        cli.dev_test
      end

      aggregate_failures do
        expect(output).to include('Running tests')
        expect(output).to match(/tcf-gateway|tcf-personas|tcf-workflows/)
      end
    end

    it 'supports parallel test execution' do
      output = capture_stdout do
        cli.invoke(:dev_test, [], { parallel: true })
      end

      aggregate_failures do
        expect(output).to include('parallel')
        expect(output).to include('Running tests')
      end
    end

    it 'supports service-specific testing' do
      output = capture_stdout do
        cli.invoke(:dev_test, ['tcf-gateway'])
      end

      aggregate_failures do
        expect(output).to include('tcf-gateway')
        expect(output).to include('Running tests')
      end
    end

    it 'supports integration testing mode' do
      output = capture_stdout do
        cli.invoke(:dev_test, [], { integration: true })
      end

      aggregate_failures do
        expect(output).to include('integration')
        expect(output).to include('Running')
      end
    end
  end

  describe '#dev_migrate' do
    it 'has dev migrate command available' do
      expect(cli).to respond_to(:dev_migrate)
    end

    it 'coordinates database migrations across all services' do
      output = capture_stdout do
        cli.dev_migrate
      end

      aggregate_failures do
        expect(output).to include('database migrations')
        expect(output).to match(/tcf-personas|tcf-workflows|tcf-projects|tcf-context|tcf-tokens/)
      end
    end

    it 'supports service-specific migration' do
      output = capture_stdout do
        cli.invoke(:dev_migrate, ['tcf-personas'])
      end

      aggregate_failures do
        expect(output).to include('tcf-personas')
        expect(output).to include('migration')
      end
    end

    it 'supports migration rollback' do
      output = capture_stdout do
        cli.invoke(:dev_migrate, ['tcf-personas'], { rollback: 1 })
      end

      aggregate_failures do
        expect(output).to include('rollback')
        expect(output).to include('tcf-personas')
      end
    end

    it 'provides migration status information' do
      output = capture_stdout do
        cli.invoke(:dev_migrate, [], { status: true })
      end

      aggregate_failures do
        expect(output).to include('migration status')
        expect(output).to match(/pending|applied|up.to.date/)
      end
    end
  end

  describe '#dev_doctor' do
    it 'has dev doctor command available' do
      expect(cli).to respond_to(:dev_doctor)
    end

    it 'performs comprehensive environment diagnostics' do
      output = capture_stdout do
        cli.dev_doctor
      end

      aggregate_failures do
        expect(output).to include('TCF Platform Environment Diagnostics')
        expect(output).to match(/Docker|Prerequisites|Services|Database/)
      end
    end

    it 'provides detailed system information' do
      output = capture_stdout do
        cli.dev_doctor
      end

      aggregate_failures do
        expect(output).to match(/✓|✗|⚠/)  # Should have status indicators
        expect(output).to include('System')
        expect(output.lines.size).to be > 5  # Should be comprehensive
      end
    end

    it 'supports verbose diagnostic mode' do
      output = capture_stdout do
        cli.invoke(:dev_doctor, [], { verbose: true })
      end

      aggregate_failures do
        expect(output).to include('Verbose')
        expect(output.length).to be > 200  # Verbose should be much longer
      end
    end

    it 'provides quick health check mode' do
      output = capture_stdout do
        cli.invoke(:dev_doctor, [], { quick: true })
      end

      aggregate_failures do
        expect(output).to include('Quick')
        expect(output).to match(/healthy|degraded|unhealthy/)
      end
    end

    it 'checks service connectivity' do
      output = capture_stdout do
        cli.dev_doctor
      end

      aggregate_failures do
        expect(output).to match(/connectivity|connection|reachable/)
        expect(output).to include('services')
      end
    end
  end

  describe 'CLI integration with development workflow' do
    it 'provides help information for dev commands' do
      output = capture_stdout do
        cli.help('dev_setup')
      end

      expect(output).to include('dev_setup')
    end

    it 'supports command chaining workflow' do
      # Simulate a complete development workflow
      setup_output = capture_stdout { cli.dev_setup }
      test_output = capture_stdout { cli.dev_test }
      
      aggregate_failures do
        expect(setup_output).to include('Setting up')
        expect(test_output).to include('Running tests')
      end
    end

    it 'handles command failures appropriately' do
      # Even if commands fail due to missing dependencies, they should handle it gracefully
      aggregate_failures do
        expect { cli.dev_setup }.not_to raise_error
        expect { cli.dev_test }.not_to raise_error
        expect { cli.dev_migrate }.not_to raise_error
        expect { cli.dev_doctor }.not_to raise_error
      end
    end

    it 'provides consistent output formatting across dev commands' do
      setup_output = capture_stdout { cli.dev_setup }
      doctor_output = capture_stdout { cli.dev_doctor }

      aggregate_failures do
        expect(setup_output).to match(/TCF/)
        expect(doctor_output).to match(/TCF/)
        # Both should have consistent formatting
        expect(setup_output.lines.first).to match(/[A-Z]/)
        expect(doctor_output.lines.first).to match(/[A-Z]/)
      end
    end
  end
end