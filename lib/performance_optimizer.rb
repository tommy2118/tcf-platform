# frozen_string_literal: true

module TcfPlatform
  # Performance optimization utilities for configuration operations
  class PerformanceOptimizer
    class << self
      def with_caching(cache_key, ttl: 300, &block)
        @config_cache ||= {}
        cache_entry = @config_cache[cache_key]

        return cache_entry[:value] if cache_entry && (Time.now - cache_entry[:timestamp]) < ttl

        result = block.call
        @config_cache[cache_key] = {
          value: result,
          timestamp: Time.now
        }

        result
      end

      def clear_cache(pattern = nil)
        @config_cache ||= {}
        @validation_cache ||= {}

        if pattern
          @config_cache.delete_if { |key, _| key.match?(pattern) }
        else
          @config_cache.clear
        end

        @validation_cache.clear
      end

      def cache_stats
        @config_cache ||= {}
        @validation_cache ||= {}

        {
          config_cache_size: @config_cache.size,
          validation_cache_size: @validation_cache.size,
          total_memory: calculate_cache_memory_usage
        }
      end

      def optimize_file_operations(&block)
        # Batch file operations for better performance
        original_sync = $stdout.sync
        $stdout.sync = false

        begin
          result = block.call
          $stdout.flush
          result
        ensure
          $stdout.sync = original_sync
        end
      end

      def parallel_validation(items, max_threads: 4, &)
        return items.map(&) if items.size <= max_threads

        thread_pool = []
        results = Array.new(items.size)

        items.each_with_index do |item, index|
          thread_pool.shift.join if thread_pool.size >= max_threads

          thread = Thread.new do
            Thread.current[:result] = yield(item)
          end

          thread_pool << { thread: thread, index: index }
        end

        # Wait for remaining threads
        thread_pool.each do |thread_info|
          thread_info[:thread].join
          results[thread_info[:index]] = thread_info[:thread][:result]
        end

        results
      end

      def measure_performance(operation_name = 'operation')
        start_time = Time.now
        memory_before = memory_usage

        result = yield

        end_time = Time.now
        memory_after = memory_usage

        {
          result: result,
          duration: end_time - start_time,
          memory_used: memory_after - memory_before,
          operation: operation_name
        }
      end

      private

      def calculate_cache_memory_usage
        @config_cache ||= {}
        @validation_cache ||= {}

        total_size = 0

        [@config_cache, @validation_cache].each do |cache|
          cache&.each_value do |value|
            total_size += estimate_object_size(value)
          end
        end

        total_size
      end

      def estimate_object_size(obj)
        case obj
        when String
          obj.bytesize
        when Hash
          obj.to_s.bytesize
        when Array
          obj.to_s.bytesize
        else
          obj.to_s.bytesize
        end
      end

      def memory_usage
        # Simple memory tracking (platform dependent)
        if defined?(GC) && GC.respond_to?(:stat)
          GC.stat(:total_allocated_bytes) || 0
        else
          0
        end
      end
    end
  end
end
