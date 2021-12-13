# typed: true
module Datadog
  module OpenTracer
    # OpenTracing adapter for thread local scopes
    # @public_api
    class ThreadLocalScope < Scope
      # @public_api
      attr_reader \
        :finish_on_close

      # @public_api
      def initialize(
        manager:,
        span:,
        finish_on_close: true
      )
        super(manager: manager, span: span)
        @finish_on_close = finish_on_close
        @previous_scope = manager.active
      end

      # Mark the end of the active period for the current thread and Scope,
      # updating the ScopeManager#active in the process.
      #
      # NOTE: Calling close more than once on a single Scope instance leads to
      # undefined behavior.
      # @public_api
      def close
        return unless equal?(manager.active)

        span.finish if finish_on_close
        manager.send(:set_scope, @previous_scope)
      end
    end
  end
end
