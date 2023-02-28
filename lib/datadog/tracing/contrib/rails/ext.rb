module Datadog
  module Tracing
    module Contrib
      module Rails
        # Rails integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          APP = 'rails'.freeze
          ENV_ENABLED = 'DD_TRACE_RAILS_ENABLED'.freeze
          ENV_ANALYTICS_ENABLED = 'DD_TRACE_RAILS_ANALYTICS_ENABLED'.freeze
          ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_RAILS_ANALYTICS_SAMPLE_RATE'.freeze
          ENV_DISABLE = 'DISABLE_DATADOG_RAILS'.freeze
        end
      end
    end
  end
end
