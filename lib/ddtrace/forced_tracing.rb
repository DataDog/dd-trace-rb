# typed: true
require 'ddtrace/ext/manual_tracing'
require 'ddtrace/ext/priority'

module Datadog
  # Defines analytics behavior
  module ForcedTracing
    class << self
      def keep(span)
        return if span.nil? || span.context.nil?

        span.context.sampling_priority = Datadog::Ext::Priority::USER_KEEP
      end

      def drop(span)
        return if span.nil? || span.context.nil?

        span.context.sampling_priority = Datadog::Ext::Priority::USER_REJECT
      end
    end

    # Extension for Datadog::SpanOperation
    module SpanOperation
      def set_tag(key, value)
        # Configure sampling priority if they give us a forced tracing tag
        # DEV: Do not set if the value they give us is explicitly "false"
        case key
        when Ext::ManualTracing::TAG_KEEP
          ForcedTracing.keep(self) unless value == false
        when Ext::ManualTracing::TAG_DROP
          ForcedTracing.drop(self) unless value == false
        else
          # Otherwise, set the tag normally.
          super if defined?(super)
        end
      end
    end
  end
end
