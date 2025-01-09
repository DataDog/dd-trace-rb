# frozen_string_literal: true

module Datadog
  module AppSec
    # Write desciption TODO
    class Context
      InactiveScopeError = Class.new(StandardError)
      ActiveScopeError = Class.new(StandardError)

      attr_reader :trace, :service_entry_span, :processor_context

      def initialize(trace, service_entry_span, processor_context)
        @trace = trace
        @service_entry_span = service_entry_span
        @processor_context = processor_context
      end

      def finalize
        @processor_context.finalize
      end

      class << self
        def activate_context(trace, service_entry_span, processor)
          raise ActiveScopeError, 'another scope is active, nested scopes are not supported' if active_context

          context = processor.new_context
          self.active_context = new(trace, service_entry_span, context)
        end

        def deactivate_context
          raise InactiveScopeError, 'no context is active, nested contexts are not supported' unless active_context

          context = active_context

          reset_active_context

          context.finalize
        end

        def active_context
          Thread.current[Ext::ACTIVE_CONTEXT_KEY]
        end

        private

        def active_context=(context)
          raise ArgumentError, 'not a Datadog::AppSec::Context' unless context.instance_of?(Context)

          Thread.current[Ext::ACTIVE_CONTEXT_KEY] = context
        end

        def reset_active_context
          Thread.current[Ext::ACTIVE_CONTEXT_KEY] = nil
        end
      end
    end
  end
end
