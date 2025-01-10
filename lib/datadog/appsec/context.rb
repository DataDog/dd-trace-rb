# frozen_string_literal: true

module Datadog
  module AppSec
    # This class accumulates the context over the request life-cycle and exposes
    # interface sufficient for instrumentation to perform threat detection.
    class Context
      ActiveContextError = Class.new(StandardError)

      attr_reader :trace, :service_entry_span, :processor_context

      class << self
        def activate(context)
          raise ArgumentError, 'not a Datadog::AppSec::Context' unless context.instance_of?(Context)
          raise ActiveContextError, 'another context is active, nested contexts are not supported' if active

          Thread.current[Ext::ACTIVE_CONTEXT_KEY] = context
        end

        def deactivate
          active&.finalize
        ensure
          Thread.current[Ext::ACTIVE_CONTEXT_KEY] = nil
        end

        def active
          Thread.current[Ext::ACTIVE_CONTEXT_KEY]
        end
      end

      def initialize(trace, span, security_engine)
        @trace = trace
        @span = span
        @security_engine = security_engine

        # TODO: Rename
        @service_entry_span = span
        @processor_context = security_engine.new_context
      end

      def finalize
        @processor_context.finalize
      end
    end
  end
end
