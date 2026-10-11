# frozen_string_literal: true

module Datadog
  module DI
    # An adapter to convert procs to responders.
    #
    # Used in test suite and benchmarks.
    #
    # @api private
    class ProcResponder
      def initialize(executed_proc, failed_proc = nil, emitted_proc = nil)
        @executed_proc = executed_proc
        @failed_proc = failed_proc
        @emitted_proc = emitted_proc
      end

      attr_reader :executed_proc
      attr_reader :failed_proc
      attr_reader :emitted_proc

      def probe_executed_callback(context)
        executed_proc.call(context)
      end

      def probe_expression_evaluation_failed_callback(context, _expr, exc)
        if failed_proc.nil?
          raise NotImplementedError, "Failed proc not provided"
        end

        failed_proc.call(context, exc)
      end

      def probe_metric_emitted_callback(probe)
        if emitted_proc.nil?
          raise NotImplementedError, "Emitted proc not provided"
        end

        emitted_proc.call(probe)
      end

      def probe_disabled_callback(probe, duration)
        raise NotImplementedError
      end
    end
  end
end
