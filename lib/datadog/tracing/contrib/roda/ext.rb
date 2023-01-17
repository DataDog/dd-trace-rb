# typed: ignore

module Datadog
  module Tracing
    module Contrib
      module Roda
        # Roda integration constants
        module Ext
          APP = 'roda'.freeze
          ENV_ENABLED = 'DD_TRACE_RODA_ENABLED'.freeze
          ENV_ANALYTICS_ENABLED = 'DD_RODA_ANALYTICS_ENABLED'.freeze
          ENV_ANALYTICS_SAMPLE_RATE = 'DD_RODA_ANALYTICS_SAMPLE_RATE'.freeze

          SERVICE_NAME = 'roda'.freeze
          SPAN_REQUEST = 'roda.request'.freeze
        end
      end
    end
  end
end
