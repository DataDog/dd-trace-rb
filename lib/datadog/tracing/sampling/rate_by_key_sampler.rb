# typed: true
require 'datadog/tracing/sampling/sampler'
require 'datadog/tracing/sampling/rate_sampler'

module Datadog
  module Tracing
    module Sampling
      # Samples at different rates by key.
      # @public_api
      class RateByKeySampler < Sampler
        attr_reader \
          :default_key

        def initialize(default_key, default_rate = 1.0, &block)
          super()

          raise ArgumentError, 'No resolver given!' unless block

          @default_key = default_key
          @resolver = block
          @mutex = Mutex.new
          @samplers = {}

          set_rate(default_key, default_rate)
        end

        def resolve(trace)
          @resolver.call(trace)
        end

        def default_sampler
          @samplers[default_key]
        end

        def sample?(trace)
          key = resolve(trace)

          @mutex.synchronize do
            @samplers.fetch(key, default_sampler).sample?(trace)
          end
        end

        def sample!(trace)
          key = resolve(trace)

          @mutex.synchronize do
            @samplers.fetch(key, default_sampler).sample!(trace)
          end
        end

        def sample_rate(trace)
          key = resolve(trace)

          @mutex.synchronize do
            @samplers.fetch(key, default_sampler).sample_rate
          end
        end

        def update(key, rate)
          @mutex.synchronize do
            set_rate(key, rate)
          end
        end

        def update_all(rate_by_key)
          @mutex.synchronize do
            rate_by_key.each { |key, rate| set_rate(key, rate) }
          end
        end

        def delete(key)
          @mutex.synchronize do
            @samplers.delete(key)
          end
        end

        def delete_if(&block)
          @mutex.synchronize do
            @samplers.delete_if(&block)
          end
        end

        def length
          @samplers.length
        end

        private

        def set_rate(key, rate)
          @samplers[key] ||= RateSampler.new(rate)
          @samplers[key].sample_rate = rate
        end
      end
    end
  end
end
