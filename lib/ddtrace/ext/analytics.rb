module Datadog
  module Ext
    # Defines constants for trace analytics
    module Analytics
      DEFAULT_SAMPLE_RATE = 1.0
      ENV_TRACE_ANALYTICS_ENABLED = 'DD_TRACE_ANALYTICS_ENABLED'.freeze
      TAG_ENABLED = 'analytics.enabled'.freeze
      TAG_MEASURED = '_dd.measured'.freeze
      TAG_SAMPLE_RATE = '_dd1.sr.eausr'.freeze
    end
  end
end
