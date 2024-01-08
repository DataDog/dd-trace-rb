# frozen_string_literal: true

require_relative 'component'
require_relative 'http/integration'
require_relative 'http/distributed/propagation'

module Datadog
  module Tracing
    module Contrib
      # `Net/HTTP` integration public API
      # @public_api
      module HTTP
        # Inject distributed headers into the given request
        # @param digest [Datadog::Tracing::TraceDigest] the trace to inject
        # @param data [Hash] the request to inject
        def self.inject(digest, data)
          raise 'Please invoke Datadog.configure at least once before calling this method' unless @propagation

          @propagation.inject!(digest, data)
        end

        # Extract distributed headers from the given request
        # @param data [Hash] the request to extract from
        # @return [Datadog::Tracing::TraceDigest,nil] the extracted trace digest or nil if none was found
        def self.extract(data)
          raise 'Please invoke Datadog.configure at least once before calling this method' unless @propagation

          @propagation.extract(data)
        end

        Contrib::Component.register('http') do |config|
          distributed_tracing = config.tracing.distributed_tracing
          # DEV: evaluate propagation_style in case it overrides propagation_extract_style & propagation_extract_first
          distributed_tracing.propagation_style

          @propagation = HTTP::Distributed::Propagation.new(
            propagation_inject_style: distributed_tracing.propagation_inject_style,
            propagation_extract_style: distributed_tracing.propagation_extract_style,
            propagation_extract_first: distributed_tracing.propagation_extract_first
          )
        end
      end
    end
  end
end
