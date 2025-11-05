# frozen_string_literal: true

require 'zlib'

require 'datadog/core/utils/lru_cache'

module Datadog
  module OpenFeature
    module Exposures
      class Deduplicator
        DEFAULT_CACHE_LIMIT = 1_000

        def initialize(limit: DEFAULT_CACHE_LIMIT)
          @cache = Datadog::Core::Utils::LRUCache.new(limit)
          @mutex = Mutex.new
        end

        def duplicate?(flag_key, targeting_key, allocation_key:, variation_key:)
          cache_key = digest(flag_key, targeting_key)
          cache_digest = digest(allocation_key, variation_key)

          stored = @cache[cache_key]
          return true if stored == cache_digest

          @mutex.synchronize { @cache.store(cache_key, cache_digest) }
          false
        end

        private

        def digest(left, right)
          Zlib.crc32(left + right)
        end
      end
    end
  end
end
