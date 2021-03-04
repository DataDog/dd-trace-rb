module Datadog
  module Contrib
    # Support methods for writing library integrations.
    module Support
      module_function

      # Ensures that there's no open span in the currently
      # active context.
      # This method is a safe-guard to ensure that top-level
      # integrations have a clean context to process subsequent
      # events.
      # In such context, open spans would indicate a failure
      # to properly close a span, which can likely be a bug.
      #
      # DEV: This method should not be required, as all spans
      # should be properly closed, but we currently don't have
      # data collected to prove if that's the case.
      #
      # @param tracer [Datadog::Tracer] active tracer instance
      # @param integration_name [String] name of caller integration
      def ensure_finished_context!(tracer, integration_name)
        unless tracer.call_context.empty?
          Datadog.health_metrics.unfinished_context(
            1, tags: ["integration:#{integration_name}"]
          )
        end

        tracer.provider.context = Context.new
      end
    end
  end
end
