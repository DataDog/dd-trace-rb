# frozen_string_literal: true

require_relative '../../core/utils/lru_cache'

module Datadog
  module OpenFeature
    module Exposures
      # This class is a deduplication buffer based on LRU cache for exposure events
      class Deduplicator
        DEFAULT_CACHE_LIMIT = 1_000

        def initialize(limit: DEFAULT_CACHE_LIMIT)
          @cache = Datadog::Core::Utils::LRUCache.new(limit)
          @mutex = Mutex.new
        end

        def duplicate?(key, value)
          @mutex.synchronize do
            stored = @cache[key]
            return true if stored == value

            @cache[key] = value
          end

          false
        end
      end
    end
  end
end
