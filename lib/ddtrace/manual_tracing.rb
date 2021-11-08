# typed: true
require 'ddtrace/ext/priority'

module Datadog
  # Defines analytics behavior
  module ManualTracing
    class << self
      # TODO: Assumes it will have access to the context from the span.
      #       This won't be true in the future. Will need to change this.
      def keep(span_op)
        return if span_op.nil? || !span_op.respond_to?(:context) || span_op.context.nil?

        span_op.context.sampling_priority = Datadog::Ext::Priority::USER_KEEP
      end

      def drop(span_op)
        return if span_op.nil? || !span_op.respond_to?(:context) || span_op.context.nil?

        span_op.context.sampling_priority = Datadog::Ext::Priority::USER_REJECT
      end
    end
  end
end
