# frozen_string_literal: true

require 'zlib'
require_relative '../../core/utils/lru_cache'

module Datadog
  module OpenFeature
    module Exposures
      class Deduplicator
        DEFAULT_CACHE_LIMIT = 1_000

        def initialize(limit: DEFAULT_CACHE_LIMIT)
          @cache = Datadog::Core::Utils::LRUCache.new(limit)
          @mutex = Mutex.new
        end

        def duplicate?(event)
          cache_key = digest(event.flag_key, event.targeting_key)
          cache_digest = digest(event.allocation_key, event.variation_key)

          @mutex.synchronize do
            stored = @cache[cache_key]
            return true if stored == cache_digest

            @cache[cache_key] = cache_digest
          end

          false
        end

        private

        def digest(left, right)
          Zlib.crc32("#{left}:#{right}")
        end
      end
    end
  end
end
