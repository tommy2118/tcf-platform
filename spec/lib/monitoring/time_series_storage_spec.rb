# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/monitoring/time_series_storage'

RSpec.describe TcfPlatform::Monitoring::TimeSeriesStorage do
  let(:storage) { described_class.new }
  let(:redis_client) { instance_double(Redis) }

  before do
    allow(Redis).to receive(:new).and_return(redis_client)
    allow(redis_client).to receive(:ping).and_return('PONG')
    allow(redis_client).to receive(:setex)
    allow(redis_client).to receive(:zadd)
    allow(redis_client).to receive(:zrangebyscore).and_return([])
    allow(redis_client).to receive(:mget).and_return([])
  end

  describe '#initialize' do
    it 'initializes with Redis connection' do
      expect(storage.redis).to eq(redis_client)
    end

    it 'supports custom Redis configuration' do
      custom_config = { host: 'localhost', port: 6380, db: 5 }
      allow(Redis).to receive(:new).with(custom_config).and_return(redis_client)
      
      storage = described_class.new(redis_config: custom_config)
      expect(Redis).to have_received(:new).with(custom_config)
    end

    it 'validates Redis connectivity on initialization' do
      storage # Force initialization
      expect(redis_client).to have_received(:ping)
    end

    it 'raises error if Redis is not available' do
      allow(redis_client).to receive(:ping).and_raise(Redis::CannotConnectError)
      
      expect { described_class.new }.to raise_error(TcfPlatform::Monitoring::StorageConnectionError)
    end
  end

  describe '#store_metric' do
    let(:timestamp) { Time.now.to_i }
    let(:metric_data) do
      {
        service: 'gateway',
        metric: 'cpu_percent',
        value: 45.2,
        timestamp: timestamp,
        tags: { environment: 'production' }
      }
    end

    it 'stores metric data with timestamp-based key' do
      expected_key = "metrics:gateway:cpu_percent:#{timestamp}"
      expected_data = metric_data.to_json
      
      allow(redis_client).to receive(:setex)
      
      storage.store_metric(metric_data)
      
      expect(redis_client).to have_received(:setex)
        .with(expected_key, 2592000, expected_data) # 30 days TTL
    end

    it 'adds metric to time-series index for querying' do
      index_key = 'metrics:index:gateway:cpu_percent'
      
      allow(redis_client).to receive(:setex)
      allow(redis_client).to receive(:zadd)
      
      storage.store_metric(metric_data)
      
      expect(redis_client).to have_received(:zadd)
        .with(index_key, timestamp, timestamp)
    end

    it 'supports custom TTL configuration' do
      ttl_seconds = 7200 # 2 hours
      storage = described_class.new(default_ttl: ttl_seconds)
      allow(redis_client).to receive(:setex)
      
      storage.store_metric(metric_data)
      
      expect(redis_client).to have_received(:setex)
        .with(anything, ttl_seconds, anything)
    end

    it 'validates required metric fields' do
      incomplete_data = { service: 'gateway', value: 45.2 }
      
      expect { storage.store_metric(incomplete_data) }.to raise_error(ArgumentError, /Missing required field/)
    end

    it 'handles Redis storage errors gracefully' do
      allow(redis_client).to receive(:setex).and_raise(Redis::TimeoutError)
      
      expect { storage.store_metric(metric_data) }.to raise_error(TcfPlatform::Monitoring::StorageError)
    end
  end

  describe '#store_batch' do
    let(:batch_metrics) do
      [
        { service: 'gateway', metric: 'cpu_percent', value: 45.2, timestamp: Time.now.to_i },
        { service: 'gateway', metric: 'memory_percent', value: 62.1, timestamp: Time.now.to_i },
        { service: 'personas', metric: 'cpu_percent', value: 38.7, timestamp: Time.now.to_i }
      ]
    end

    it 'stores multiple metrics in a single Redis transaction' do
      transaction_mock = instance_double('Redis::Transaction')
      allow(transaction_mock).to receive(:setex)
      allow(transaction_mock).to receive(:zadd)
      allow(redis_client).to receive(:multi).and_yield(transaction_mock)
      
      storage.store_batch(batch_metrics)
      
      expect(redis_client).to have_received(:multi)
      expect(transaction_mock).to have_received(:setex).exactly(3).times
    end

    it 'improves performance for large metric batches' do
      large_batch = Array.new(100) { |i| 
        { service: 'service', metric: 'test', value: i, timestamp: Time.now.to_i + i }
      }
      
      transaction_mock = instance_double('Redis::Transaction')
      allow(transaction_mock).to receive(:setex)
      allow(transaction_mock).to receive(:zadd)
      allow(redis_client).to receive(:multi).and_yield(transaction_mock)
      
      start_time = Time.now
      storage.store_batch(large_batch)
      execution_time = Time.now - start_time
      
      expect(execution_time).to be < 1.0 # Should complete in under 1 second
    end

    it 'provides atomic batch storage (all or nothing)' do
      transaction_mock = instance_double('Redis::Transaction')
      allow(transaction_mock).to receive(:setex).and_raise(Redis::TimeoutError)
      allow(transaction_mock).to receive(:zadd)
      allow(redis_client).to receive(:multi).and_yield(transaction_mock)
      
      expect { storage.store_batch(batch_metrics) }.to raise_error(TcfPlatform::Monitoring::StorageError)
    end
  end

  describe '#query_metrics' do
    let(:query_params) do
      {
        service: 'gateway',
        metric: 'cpu_percent',
        start_time: Time.now - 3600, # 1 hour ago
        end_time: Time.now,
        resolution: 300 # 5 minute intervals
      }
    end

    it 'retrieves time-series data for specified time range' do
      index_key = 'metrics:index:gateway:cpu_percent'
      expected_timestamps = [1693276800, 1693277100, 1693277400]
      
      allow(redis_client).to receive(:zrangebyscore)
        .with(index_key, query_params[:start_time].to_i, query_params[:end_time].to_i)
        .and_return(expected_timestamps.map(&:to_s))
      
      allow(redis_client).to receive(:mget).and_return([
        { value: 45.2, timestamp: 1693276800 }.to_json,
        { value: 47.8, timestamp: 1693277100 }.to_json,
        { value: 52.1, timestamp: 1693277400 }.to_json
      ])
      
      result = storage.query_metrics(query_params)
      
      aggregate_failures do
        expect(result).to be_an(Array)
        expect(result.length).to eq(3)
        expect(result.first[:value]).to eq(45.2)
        expect(result.first[:timestamp]).to eq(1693276800)
      end
    end

    it 'supports aggregation functions (avg, min, max, sum)' do
      query_with_aggregation = query_params.merge(aggregation: 'avg')
      
      # Mock Redis calls for aggregation test
      index_key = 'metrics:index:gateway:cpu_percent'
      expected_timestamps = [1693276800, 1693277100, 1693277400]
      
      allow(redis_client).to receive(:zrangebyscore)
        .with(index_key, query_params[:start_time].to_i, query_params[:end_time].to_i)
        .and_return(expected_timestamps.map(&:to_s))
      
      allow(redis_client).to receive(:mget).and_return([
        { value: 45.2, timestamp: 1693276800 }.to_json,
        { value: 47.8, timestamp: 1693277100 }.to_json,
        { value: 52.1, timestamp: 1693277400 }.to_json
      ])
      
      result = storage.query_metrics(query_with_aggregation)
      
      # Should return aggregated data points based on resolution
      expect(result).to be_an(Array)
      expect(result.first).to include(:aggregated_value)
    end

    it 'handles empty result sets gracefully' do
      allow(redis_client).to receive(:zrangebyscore).and_return([])
      
      result = storage.query_metrics(query_params)
      
      expect(result).to be_empty
    end

    it 'validates query parameters' do
      invalid_query = query_params.merge(start_time: Time.now, end_time: Time.now - 3600)
      
      expect { storage.query_metrics(invalid_query) }.to raise_error(ArgumentError, /Start time must be before end time/)
    end

    it 'limits query result size to prevent memory issues' do
      # Mock large dataset
      large_result = Array.new(10_000) { rand(1..100).to_s }
      allow(redis_client).to receive(:zrangebyscore).and_return(large_result)
      
      result = storage.query_metrics(query_params)
      
      expect(result.length).to be <= 5000 # Should be limited to reasonable size
    end
  end

  describe '#aggregate_metrics' do
    let(:raw_data) do
      [
        { value: 45.2, timestamp: 1693276800 },
        { value: 47.8, timestamp: 1693276860 },
        { value: 52.1, timestamp: 1693276920 },
        { value: 49.5, timestamp: 1693276980 }
      ]
    end

    it 'calculates average aggregation' do
      result = storage.aggregate_metrics(raw_data, 'avg', 300)
      expected_avg = (45.2 + 47.8 + 52.1 + 49.5) / 4
      
      expect(result.first[:aggregated_value]).to be_within(0.01).of(expected_avg)
    end

    it 'calculates min and max aggregations' do
      min_result = storage.aggregate_metrics(raw_data, 'min', 300)
      max_result = storage.aggregate_metrics(raw_data, 'max', 300)
      
      aggregate_failures do
        expect(min_result.first[:aggregated_value]).to eq(45.2)
        expect(max_result.first[:aggregated_value]).to eq(52.1)
      end
    end

    it 'groups data points by resolution intervals' do
      # With 5-minute (300s) resolution, should group nearby points
      result = storage.aggregate_metrics(raw_data, 'avg', 300)
      
      # Should have fewer aggregated points than raw data points
      expect(result.length).to be <= raw_data.length
    end

    it 'handles edge cases for empty data' do
      result = storage.aggregate_metrics([], 'avg', 300)
      expect(result).to be_empty
    end
  end

  describe '#cleanup_expired_metrics' do
    it 'removes expired metrics based on TTL' do
      allow(redis_client).to receive(:scan_each).with(match: 'metrics:*').and_yield('metrics:old_key')
      allow(redis_client).to receive(:ttl).with('metrics:old_key').and_return(-1) # Expired
      allow(redis_client).to receive(:del)
      
      storage.cleanup_expired_metrics
      
      expect(redis_client).to have_received(:del).with('metrics:old_key')
    end

    it 'provides cleanup statistics' do
      keys = ['metrics:key1', 'metrics:key2', 'metrics:key3']
      allow(redis_client).to receive(:scan_each).with(match: 'metrics:*') do |&block|
        keys.each { |key| block.call(key) }
      end
      allow(redis_client).to receive(:ttl).and_return(-1, 3600, -1) # Mixed expired/active
      allow(redis_client).to receive(:del)
      
      stats = storage.cleanup_expired_metrics
      
      aggregate_failures do
        expect(stats).to include(:scanned_keys)
        expect(stats).to include(:expired_keys)
        expect(stats).to include(:deleted_keys)
        expect(stats).to include(:cleanup_duration)
      end
    end
  end

  describe '#storage_statistics' do
    it 'provides comprehensive storage usage statistics' do
      allow(redis_client).to receive(:info).and_return({
        'used_memory' => '1048576',
        'connected_clients' => '5',
        'keyspace_hits' => '12345',
        'keyspace_misses' => '678'
      })
      
      allow(redis_client).to receive(:dbsize).and_return(5000)
      
      stats = storage.storage_statistics
      
      aggregate_failures do
        expect(stats).to include(:used_memory_bytes)
        expect(stats).to include(:total_keys)
        expect(stats).to include(:connected_clients)
        expect(stats).to include(:cache_hit_rate)
        expect(stats[:used_memory_bytes]).to eq(1_048_576)
        expect(stats[:total_keys]).to eq(5000)
      end
    end
  end

  describe '#backup_storage' do
    it 'creates point-in-time backup of time-series data' do
      backup_path = '/tmp/metrics_backup.rdb'
      
      allow(redis_client).to receive(:bgsave)
      allow(redis_client).to receive(:lastsave).and_return(Time.now.to_i)
      allow(FileUtils).to receive(:cp)
      
      storage.backup_storage(backup_path)
      
      expect(redis_client).to have_received(:bgsave)
    end

    it 'validates backup completion before proceeding' do
      backup_path = '/tmp/metrics_backup.rdb'
      
      allow(redis_client).to receive(:bgsave)
      allow(redis_client).to receive(:lastsave).and_return(Time.now.to_i - 3600) # Old backup
      
      expect { storage.backup_storage(backup_path) }.to raise_error(TcfPlatform::Monitoring::StorageError, /Backup failed/)
    end
  end
end