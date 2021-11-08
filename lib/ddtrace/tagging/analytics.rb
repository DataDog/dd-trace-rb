require 'ddtrace/ext/analytics'
require 'ddtrace/analytics'

module Datadog
  module Tagging
    # Defines analytics tagging behavior
    module Analytics
      def set_tag(key, value)
        case key
        when Ext::Analytics::TAG_ENABLED
          # If true, set rate to 1.0, otherwise set 0.0.
          value = value == true ? Ext::Analytics::DEFAULT_SAMPLE_RATE : 0.0
          Datadog::Analytics.set_sample_rate(self, value)
        when Ext::Analytics::TAG_SAMPLE_RATE
          Datadog::Analytics.set_sample_rate(self, value)
        else
          super if defined?(super)
        end
      end
    end
  end
end
