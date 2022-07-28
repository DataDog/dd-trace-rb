# typed: true

require_relative '../../core'
require_relative 'rate_by_key_sampler'

module Datadog
  module Tracing
    module Sampling
      # {Datadog::Tracing::Sampling::RateByServiceSampler} samples different services at different rates
      # @public_api
      class RateByServiceSampler < RateByKeySampler
        DEFAULT_KEY = 'service:,env:'.freeze

        def initialize(default_rate = 1.0, options = {})
          super(DEFAULT_KEY, default_rate, &method(:key_for))
          @env = options[:env]
        end

        def update(rate_by_service)
          # Remove any old services
          delete_if { |key, _| key != DEFAULT_KEY && !rate_by_service.key?(key) }

          # Update each service rate
          update_all(rate_by_service)

          # Emit metric for service cache size
          Datadog.health_metrics.sampling_service_cache_length(length)
        end

        private

        def key_for(trace)
          # Resolve env dynamically, if Proc is given.
          env = @env.is_a?(Proc) ? @env.call : @env

          "service:#{trace.service},env:#{env}"
        end
      end
    end
  end
end
