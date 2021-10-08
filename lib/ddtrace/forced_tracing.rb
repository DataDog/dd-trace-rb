# typed: true
require 'ddtrace/ext/priority'

module Datadog
  # Defines analytics behavior
  module ForcedTracing
    class << self
      def keep(span_op)
        return if span_op.nil? || span_op.context.nil?

        span_op.context.sampling_priority = Datadog::Ext::Priority::USER_KEEP
      end

      def drop(span_op)
        return if span_op.nil? || span_op.context.nil?

        span_op.context.sampling_priority = Datadog::Ext::Priority::USER_REJECT
      end
    end
  end
end
