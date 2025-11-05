# frozen_string_literal: true

require 'zlib'
require 'thread'

require 'datadog/appsec/api_security/lru_cache'

require_relative 'event'

module Datadog
  module OpenFeature
    module Exposures
      class Reporter
        DEFAULT_CACHE_LIMIT = 1_000

        def initialize(worker:, cache: nil, logger: Datadog.logger, time_provider: Time)
          @worker = worker
          @logger = logger
          @time_provider = time_provider
          @cache = cache || Datadog::AppSec::APISecurity::LRUCache.new(DEFAULT_CACHE_LIMIT)
          @cache_mutex = Mutex.new
        end

        def report(result:, context: nil)
          payload = normalize(result, context)
          return false if payload.nil?

          cache_key = payload[:cache_key]
          digest = payload[:digest]

          return false if cache_key && digest && duplicate?(cache_key, digest)

          event = build_event(payload)
          return false if event.nil?

          @worker.enqueue(event)
        rescue => e
          @logger.debug { "OpenFeature: Reporter failed to enqueue exposure: #{e.class}: #{e.message}" }
          false
        end

        def flush
          @cache_mutex.synchronize { @cache.clear }
        end

        private

        def duplicate?(cache_key, digest)
          @cache_mutex.synchronize do
            stored = @cache[cache_key]
            return true if stored == digest

            @cache.store(cache_key, digest)
            false
          end
        end

        def normalize(result, context)
          data = ensure_hash(result)
          result_data = ensure_hash(data[:result] || data['result'])
          flag_metadata = ensure_hash(result_data[:flagMetadata] || result_data['flagMetadata'])

          flag_key = data[:flag] || data['flag']
          subject_id = extract_subject_id(data, context)
          allocation_key = flag_metadata[:allocationKey] || flag_metadata['allocationKey']
          evaluation_key = result_data[:variant] || result_data['variant']

          return nil if flag_key.nil? || subject_id.nil?

          variant = evaluation_key || result_data[:value] || result_data['value']
          variant_key = variant.nil? ? nil : variant.to_s
          return nil if variant_key.nil?

          {
            flag_key: flag_key,
            subject_id: subject_id,
            subject_type: nil,
            subject_attributes: extract_attributes(data, context),
            allocation_key: allocation_key,
            variant_key: variant_key,
            cache_key: cache_key(flag_key, subject_id),
            digest: allocation_key.nil? ? nil : digest(allocation_key, variant_key)
          }
        end

        def build_event(payload)
          Event.new(
            timestamp: @time_provider.now,
            allocation_key: payload[:allocation_key],
            flag_key: payload[:flag_key],
            variant_key: payload[:variant_key],
            subject_id: payload[:subject_id],
            subject_type: payload[:subject_type],
            subject_attributes: payload[:subject_attributes]
          )
        end

        def extract_subject_id(data, context)
          data[:targetingKey] || data['targetingKey'] || context_value(context, :targeting_key) ||
            context_value(context, :targetingKey) || context_value(context, :targetingkey)
        end

        def extract_attributes(data, context)
          attributes = data[:attributes] || data['attributes']
          return attributes if attributes.is_a?(Hash)

          context_value(context, :attributes).is_a?(Hash) ? context_value(context, :attributes) : nil
        end

        def context_value(context, key)
          case context
          when Hash
            context[key] || context[key.to_s]
          else
            context.respond_to?(key) ? context.public_send(key) : nil
          end
        end

        def ensure_hash(value)
          value.is_a?(Hash) ? value : {}
        end

        def cache_key(flag_key, subject_id)
          return nil if flag_key.nil? || subject_id.nil?

          "#{flag_key}:#{subject_id}"
        end

        def digest(allocation_key, evaluation_key)
          Zlib.crc32("#{allocation_key}:#{evaluation_key}")
        end
      end
    end
  end
end
