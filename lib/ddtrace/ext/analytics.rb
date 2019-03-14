module Datadog
  module Ext
    # Defines constants for trace analytics
    module Analytics
      ENV_TRACE_ANALYTICS_ENABLED = 'DD_TRACE_ANALYTICS_ENABLED'.freeze
      # Tag for sample rate; used by agent to determine whether analytics event is emitted.
      TAG_SAMPLE_RATE = '_dd1.sr.eausr'.freeze
    end
  end
end
