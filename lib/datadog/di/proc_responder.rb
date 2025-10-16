# frozen_string_literal: true

module Datadog
  module DI
    # An adapter to convert procs to responders.
    #
    # Used in test suite and benchmarks.
    #
    # @api private
    class ProcResponder
      def initialize(executed_proc, failed_proc = nil)
        @executed_proc = executed_proc
        @failed_proc = failed_proc
      end

      attr_reader :executed_proc
      attr_reader :failed_proc

      def probe_executed_callback(context)
        executed_proc.call(context)
      end

      def probe_condition_evaluation_failed_callback(context, exc)
        if failed_proc.nil?
          raise NotImplementedError, "Failed proc not provided"
        end

        failed_proc.call(context, exc)
      end
    end
  end
end
