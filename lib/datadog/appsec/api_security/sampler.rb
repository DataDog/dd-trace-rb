# frozen_string_literal: true

require 'zlib'
require_relative 'lru_cache'

module Datadog
  module AppSec
    module APISecurity
      # A thread-local sampler for API security based on defined delay between
      # samples with caching capability.
      class Sampler
        THREAD_KEY = :datadog_appsec_api_security_sampler
        MAX_CACHE_SIZE = 4096

        class << self
          def thread_local
            Thread.current.thread_variable_get(THREAD_KEY)
          end

          def activate(sampler)
            Thread.current.thread_variable_set(THREAD_KEY, sampler)
          end

          def deactivate
            Thread.current.thread_variable_set(THREAD_KEY, nil)
          end
        end

        def initialize(sample_delay)
          raise ArgumentError, 'sample_delay must be an Integer' unless sample_delay.is_a?(Integer)

          @cache = LRUCache.new(MAX_CACHE_SIZE)
          @sample_delay_seconds = sample_delay
        end

        # TODO: 1. Make sure that all contribs Gateway::Request have the same interface
        #       2. Make sure that Gateway::Response have the same interface
        #       3. Add request.route_path that does not exist and must be implemented
        # HACK: We agreed to write into env of the request in order to carry over
        #       the request route path which must be computed by the corresponding
        #       contrib or red from the tag `http.route` if exists
        def sample?(request, response)
          key = Zlib.crc32("#{request.method}#{request.route_path}#{response.status}")
          current_timestamp = Time.now.to_i
          cached_timestamp = @cache[key] || 0

          return false if current_timestamp - cached_timestamp <= @sample_delay_seconds

          @cache.store(key, current_timestamp)
          true
        end
      end
    end
  end
end
