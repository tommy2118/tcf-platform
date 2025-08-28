# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/test_coordinator'
require_relative '../../lib/migration_manager'

RSpec.describe TcfPlatform::TestCoordinator do
  let(:config_manager) { TcfPlatform::ConfigManager.load_environment('test') }
  let(:test_coordinator) { described_class.new(config_manager) }

  describe '#run_all_tests' do
    it 'executes tests across all TCF services' do
      expect(test_coordinator).to respond_to(:run_all_tests)
      
      result = test_coordinator.run_all_tests
      
      aggregate_failures do
        expect(result).to be_a(Hash)
        expect(result).to have_key(:status)
        expect(result).to have_key(:services_tested)
        expect(result).to have_key(:total_tests)
        expect(result).to have_key(:passed_tests)
        expect(result).to have_key(:failed_tests)
        expect(result[:services_tested]).to be_an(Array)
      end
    end

    it 'supports parallel test execution' do
      result = test_coordinator.run_all_tests(parallel: true)
      
      aggregate_failures do
        expect(result[:execution_mode]).to eq('parallel')
        expect(result[:services_tested]).to be_an(Array)
        expect(result[:execution_time]).to be_a(Numeric)
      end
    end

    it 'handles service test failures gracefully' do
      result = test_coordinator.run_all_tests
      
      # Even if individual service tests fail, the coordinator should handle it
      aggregate_failures do
        expect(['success', 'failure', 'partial']).to include(result[:status])
        expect(result).to have_key(:failed_services)
        expect(result[:failed_services]).to be_an(Array)
      end
    end
  end

  describe '#run_service_tests' do
    it 'runs tests for a specific service' do
      expect(test_coordinator).to respond_to(:run_service_tests)
      
      result = test_coordinator.run_service_tests('tcf-gateway')
      
      aggregate_failures do
        expect(result).to be_a(Hash)
        expect(result).to have_key(:service)
        expect(result).to have_key(:status)
        expect(result).to have_key(:test_count)
        expect(result).to have_key(:passed)
        expect(result).to have_key(:failed)
        expect(result[:service]).to eq('tcf-gateway')
      end
    end

    it 'validates service exists before running tests' do
      result = test_coordinator.run_service_tests('invalid-service')
      
      aggregate_failures do
        expect(result[:status]).to eq('error')
        expect(result[:error]).to include('Unknown service')
      end
    end
  end

  describe '#run_integration_tests' do
    it 'executes cross-service integration tests' do
      expect(test_coordinator).to respond_to(:run_integration_tests)
      
      result = test_coordinator.run_integration_tests
      
      aggregate_failures do
        expect(result).to be_a(Hash)
        expect(result).to have_key(:status)
        expect(result).to have_key(:test_suites)
        expect(result[:test_suites]).to be_an(Array)
        expect(result).to have_key(:integration_scenarios)
      end
    end

    it 'validates service dependencies for integration tests' do
      result = test_coordinator.run_integration_tests(['tcf-gateway', 'tcf-personas'])
      
      aggregate_failures do
        expect(result).to have_key(:dependency_check)
        expect([true, false]).to include(result[:dependency_check])
        expect(result).to have_key(:services_involved)
        expect(result[:services_involved]).to include('tcf-gateway', 'tcf-personas')
      end
    end
  end

  describe '#test_status' do
    it 'provides comprehensive test status across all services' do
      expect(test_coordinator).to respond_to(:test_status)
      
      result = test_coordinator.test_status
      
      aggregate_failures do
        expect(result).to be_a(Hash)
        expect(result).to have_key(:last_run)
        expect(result).to have_key(:service_status)
        expect(result[:service_status]).to be_a(Hash)
        expect(result).to have_key(:overall_health)
      end
    end
  end
end

RSpec.describe TcfPlatform::MigrationManager do
  let(:config_manager) { TcfPlatform::ConfigManager.load_environment('test') }
  let(:migration_manager) { described_class.new(config_manager) }

  describe '#migrate_all_databases' do
    it 'coordinates database migrations across all TCF services' do
      expect(migration_manager).to respond_to(:migrate_all_databases)
      
      result = migration_manager.migrate_all_databases
      
      aggregate_failures do
        expect(result).to be_a(Hash)
        expect(result).to have_key(:status)
        expect(result).to have_key(:services_migrated)
        expect(result).to have_key(:total_migrations_applied)
        expect(result[:services_migrated]).to be_an(Array)
      end
    end

    it 'handles migration dependencies between services' do
      result = migration_manager.migrate_all_databases
      
      aggregate_failures do
        expect(result).to have_key(:dependency_order)
        expect(result[:dependency_order]).to be_an(Array)
        expect(result).to have_key(:migration_sequence)
      end
    end

    it 'provides detailed migration status for each service' do
      result = migration_manager.migrate_all_databases
      
      result[:services_migrated].each do |service_result|
        aggregate_failures do
          expect(service_result).to have_key(:service)
          expect(service_result).to have_key(:status)
          expect(service_result).to have_key(:migrations_applied)
          expect(['success', 'failed', 'skipped']).to include(service_result[:status])
        end
      end
    end
  end

  describe '#migrate_service' do
    it 'runs migrations for a specific service database' do
      expect(migration_manager).to respond_to(:migrate_service)
      
      result = migration_manager.migrate_service('tcf-personas')
      
      aggregate_failures do
        expect(result).to be_a(Hash)
        expect(result).to have_key(:service)
        expect(result).to have_key(:status)
        expect(result).to have_key(:database_url)
        expect(result[:service]).to eq('tcf-personas')
      end
    end

    it 'validates database connectivity before migration' do
      result = migration_manager.migrate_service('tcf-gateway')
      
      aggregate_failures do
        expect(result).to have_key(:connectivity_check)
        expect([true, false]).to include(result[:connectivity_check])
        expect(result).to have_key(:database_exists)
      end
    end
  end

  describe '#rollback_migrations' do
    it 'supports rollback of database migrations' do
      expect(migration_manager).to respond_to(:rollback_migrations)
      
      result = migration_manager.rollback_migrations('tcf-personas', steps: 1)
      
      aggregate_failures do
        expect(result).to be_a(Hash)
        expect(result).to have_key(:service)
        expect(result).to have_key(:status)
        expect(result).to have_key(:rollback_steps)
        expect(result[:rollback_steps]).to eq(1)
      end
    end

    it 'validates rollback safety before execution' do
      result = migration_manager.rollback_migrations('tcf-workflows', steps: 5)
      
      aggregate_failures do
        expect(result).to have_key(:safety_check)
        expect([true, false]).to include(result[:safety_check])
        expect(result).to have_key(:available_rollbacks)
      end
    end
  end

  describe '#migration_status' do
    it 'provides migration status for all service databases' do
      expect(migration_manager).to respond_to(:migration_status)
      
      result = migration_manager.migration_status
      
      aggregate_failures do
        expect(result).to be_a(Hash)
        expect(result).to have_key(:services)
        expect(result[:services]).to be_a(Hash)
        expect(result).to have_key(:overall_status)
      end
    end

    it 'shows pending migrations for each service' do
      result = migration_manager.migration_status
      
      result[:services].each do |service_name, service_status|
        aggregate_failures do
          expect(service_status).to have_key(:pending_migrations)
          expect(service_status).to have_key(:applied_migrations)
          expect(service_status[:pending_migrations]).to be_an(Array)
          expect(service_status[:applied_migrations]).to be_an(Array)
        end
      end
    end
  end
end