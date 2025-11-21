# frozen_string_literal: true

require 'forwardable'

module Datadog
  module Core
    module Utils
      # An LRU (Least Recently Used) cache implementation that relies on the
      # Ruby 1.9+ `Hash` implementation that guarantees insertion order.
      #
      # WARNING: This implementation is NOT thread-safe and should be used
      #          in a single-threaded context or guarded by Mutex.
      class LRUCache
        extend Forwardable

        def_delegators :@store, :clear, :empty?

        def initialize(max_size)
          raise ArgumentError, 'max_size must be an Integer' unless max_size.is_a?(Integer)
          raise ArgumentError, 'max_size must be greater than 0' if max_size <= 0

          @max_size = max_size
          @store = {}
        end

        # NOTE: Accessing a key moves it to the end of the list.
        def [](key)
          if (entry = @store.delete(key))
            @store[key] = entry
          end
        end

        def []=(key, value)
          if @store.delete(key)
            @store[key] = value
          else
            # NOTE: evict the oldest entry if store reached the maximum allowed size
            @store.shift if @store.size >= @max_size
            @store[key] = value
          end
        end
      end
    end
  end
end
