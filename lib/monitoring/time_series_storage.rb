# frozen_string_literal: true

require 'redis'
require 'json'

module TcfPlatform
  module Monitoring
    # Redis-based time-series storage for metrics data
    class TimeSeriesStorage
      DEFAULT_CONFIG = {
        host: 'localhost',
        port: 6379,
        db: 0
      }.freeze

      DEFAULT_TTL = 2_592_000 # 30 days in seconds
      MAX_QUERY_RESULTS = 5_000

      attr_reader :redis

      def initialize(redis_config: {}, default_ttl: DEFAULT_TTL)
        config = DEFAULT_CONFIG.merge(redis_config)
        @redis = Redis.new(config)
        @default_ttl = default_ttl

        # Validate connectivity
        ping
      rescue Redis::CannotConnectError => e
        raise StorageConnectionError, "Failed to connect to Redis: #{e.message}"
      end

      def ping
        @redis.ping
      end

      def store_metric(metric_data)
        validate_metric_data!(metric_data)

        key = build_metric_key(metric_data)
        value = metric_data.to_json

        begin
          @redis.setex(key, @default_ttl, value)
          
          # Add to time-series index for efficient querying
          add_to_time_series_index(metric_data)
        rescue Redis::BaseError => e
          raise StorageError, "Failed to store metric: #{e.message}"
        end
      end

      def store_batch(metrics_batch)
        return if metrics_batch.empty?

        begin
          @redis.multi do |transaction|
            metrics_batch.each do |metric_data|
              validate_metric_data!(metric_data)
              
              key = build_metric_key(metric_data)
              value = metric_data.to_json
              
              transaction.setex(key, @default_ttl, value)
              transaction.zadd(
                build_index_key(metric_data),
                metric_data[:timestamp],
                metric_data[:timestamp]
              )
            end
          end
        rescue Redis::BaseError => e
          raise StorageError, "Failed to store batch: #{e.message}"
        end
      end

      def query_metrics(query_params)
        validate_query_params!(query_params)

        index_key = build_index_key(query_params)
        start_time = query_params[:start_time].to_i
        end_time = query_params[:end_time].to_i

        # Get timestamps in range
        timestamps = @redis.zrangebyscore(index_key, start_time, end_time)
        return [] if timestamps.empty?

        # Limit results to prevent memory issues
        timestamps = timestamps.first(MAX_QUERY_RESULTS) if timestamps.size > MAX_QUERY_RESULTS

        # Fetch metric data
        keys = timestamps.map { |ts| build_metric_key_from_parts(query_params, ts) }
        raw_data = @redis.mget(keys).compact.map { |json| JSON.parse(json, symbolize_names: true) }

        # Apply aggregation if requested
        if query_params[:aggregation]
          aggregate_metrics(raw_data, query_params[:aggregation], query_params[:resolution] || 300)
        else
          raw_data
        end
      end

      def aggregate_metrics(raw_data, aggregation_type, resolution_seconds)
        return [] if raw_data.empty?

        # Group data by time buckets based on resolution
        buckets = group_by_time_buckets(raw_data, resolution_seconds)

        # Apply aggregation function to each bucket
        buckets.map do |bucket_timestamp, values|
          aggregated_value = case aggregation_type
                           when 'avg'
                             values.sum { |v| v[:value] } / values.size.to_f
                           when 'min'
                             values.map { |v| v[:value] }.min
                           when 'max'
                             values.map { |v| v[:value] }.max
                           when 'sum'
                             values.sum { |v| v[:value] }
                           else
                             raise ArgumentError, "Unsupported aggregation: #{aggregation_type}"
                           end

          {
            timestamp: bucket_timestamp,
            aggregated_value: aggregated_value,
            sample_count: values.size
          }
        end
      end

      def cleanup_expired_metrics(dry_run: false)
        start_time = Time.now
        scanned_keys = 0
        expired_keys = 0
        deleted_keys = 0

        @redis.scan_each(match: 'metrics:*') do |key|
          scanned_keys += 1
          ttl = @redis.ttl(key)
          
          if ttl == -1 # Key has no expiration (expired)
            expired_keys += 1
            unless dry_run
              @redis.del(key)
              deleted_keys += 1
            end
          end
        end

        cleanup_duration = Time.now - start_time

        {
          scanned_keys: scanned_keys,
          expired_keys: expired_keys,
          deleted_keys: deleted_keys,
          cleanup_duration: cleanup_duration.round(2)
        }
      end

      def storage_statistics
        info = @redis.info

        used_memory = info['used_memory']&.to_i || 0
        connected_clients = info['connected_clients']&.to_i || 0
        keyspace_hits = info['keyspace_hits']&.to_i || 0
        keyspace_misses = info['keyspace_misses']&.to_i || 0
        
        total_operations = keyspace_hits + keyspace_misses
        hit_rate = total_operations > 0 ? (keyspace_hits.to_f / total_operations * 100).round(2) : 0.0

        {
          used_memory_bytes: used_memory,
          total_keys: @redis.dbsize,
          connected_clients: connected_clients,
          cache_hit_rate: hit_rate
        }
      end

      def backup_storage(backup_path)
        # Trigger background save
        @redis.bgsave

        # Wait for backup to complete by checking lastsave timestamp
        last_save_before = @redis.lastsave
        max_wait = 60 # Maximum 60 seconds wait

        start_time = Time.now
        loop do
          sleep 1
          current_save_time = @redis.lastsave
          
          # Backup completed if lastsave timestamp changed
          break if current_save_time > last_save_before
          
          # Timeout protection
          if Time.now - start_time > max_wait
            raise StorageError, "Backup failed to complete within #{max_wait} seconds"
          end
        end

        # In a real implementation, you'd copy the RDB file to backup_path
        # FileUtils.cp('/var/lib/redis/dump.rdb', backup_path)
      end

      private

      def validate_metric_data!(metric_data)
        required_fields = %i[service metric value timestamp]
        missing_fields = required_fields - metric_data.keys
        
        unless missing_fields.empty?
          raise ArgumentError, "Missing required field(s): #{missing_fields.join(', ')}"
        end
      end

      def validate_query_params!(params)
        if params[:start_time] >= params[:end_time]
          raise ArgumentError, "Start time must be before end time"
        end
      end

      def build_metric_key(metric_data)
        "metrics:#{metric_data[:service]}:#{metric_data[:metric]}:#{metric_data[:timestamp]}"
      end

      def build_metric_key_from_parts(query_params, timestamp)
        "metrics:#{query_params[:service]}:#{query_params[:metric]}:#{timestamp}"
      end

      def build_index_key(data)
        service = data[:service] || data['service']
        metric = data[:metric] || data['metric']
        "metrics:index:#{service}:#{metric}"
      end

      def add_to_time_series_index(metric_data)
        index_key = build_index_key(metric_data)
        timestamp = metric_data[:timestamp]
        
        @redis.zadd(index_key, timestamp, timestamp)
      end

      def group_by_time_buckets(raw_data, resolution_seconds)
        buckets = {}
        
        raw_data.each do |data_point|
          # Round timestamp down to nearest resolution boundary
          bucket_timestamp = (data_point[:timestamp] / resolution_seconds) * resolution_seconds
          buckets[bucket_timestamp] ||= []
          buckets[bucket_timestamp] << data_point
        end
        
        buckets
      end

      def fetch_raw_data(query_params)
        # This method is referenced in tests but not actually used
        # Implementing for compatibility
        query_metrics(query_params.merge(aggregation: nil))
      end
    end
  end
end