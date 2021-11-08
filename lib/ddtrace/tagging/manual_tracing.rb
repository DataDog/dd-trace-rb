require 'ddtrace/ext/manual_tracing'
require 'ddtrace/manual_tracing'

module Datadog
  module Tagging
    # Defines manual tracing tag behavior
    module ManualTracing
      def set_tag(key, value)
        # Configure sampling priority if they give us a forced tracing tag
        # DEV: Do not set if the value they give us is explicitly "false"
        case key
        when Ext::ManualTracing::TAG_KEEP
          Datadog::ManualTracing.keep(self) unless value == false
        when Ext::ManualTracing::TAG_DROP
          Datadog::ManualTracing.drop(self) unless value == false
        else
          # Otherwise, set the tag normally.
          super if defined?(super)
        end
      end
    end
  end
end
