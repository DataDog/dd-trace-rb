# frozen_string_literal: true

require_relative 'distributed/b3_multi'
require_relative 'distributed/b3_single'
require_relative 'distributed/datadog'
require_relative 'distributed/none'
require_relative 'distributed/propagation'
require_relative 'distributed/trace_context'
require_relative 'contrib/component'

module Datadog
  module Tracing
    # Namespace for distributed tracing propagation and correlation
    module Distributed
      module_function

      # Inject distributed headers into the given request
      # @param digest [Datadog::Tracing::TraceDigest] the trace to inject
      # @param data [Hash] the request to inject
      def inject(digest, data)
        raise 'Please invoke Datadog.configure at least once before calling this method' unless @propagation

        @propagation.inject!(digest, data)
      end

      # Extract distributed headers from the given request
      # @param data [Hash] the request to extract from
      # @return [Datadog::Tracing::TraceDigest,nil] the extracted trace digest or nil if none was found
      def extract(data)
        raise 'Please invoke Datadog.configure at least once before calling this method' unless @propagation

        @propagation.extract(data)
      end

      Contrib::Component.register('distributed') do |config|
        tracing = config.tracing
        # DEV: evaluate propagation_style in case it overrides propagation_style_extract & propagation_extract_first
        tracing.propagation_style

        @propagation = Propagation.new(
          propagation_styles: {
            Configuration::Ext::Distributed::PROPAGATION_STYLE_B3_MULTI_HEADER =>
              B3Multi.new(fetcher: Fetcher),
            Configuration::Ext::Distributed::PROPAGATION_STYLE_B3_SINGLE_HEADER =>
              B3Single.new(fetcher: Fetcher),
            Configuration::Ext::Distributed::PROPAGATION_STYLE_DATADOG =>
              Datadog.new(fetcher: Fetcher),
            Configuration::Ext::Distributed::PROPAGATION_STYLE_TRACE_CONTEXT =>
              TraceContext.new(fetcher: Fetcher),
            Configuration::Ext::Distributed::PROPAGATION_STYLE_NONE => None.new
          },
          propagation_style_inject: tracing.propagation_style_inject,
          propagation_style_extract: tracing.propagation_style_extract,
          propagation_extract_first: tracing.propagation_extract_first
        )
      end
    end
  end
end
