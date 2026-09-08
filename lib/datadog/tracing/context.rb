# frozen_string_literal: true

require_relative "../core/utils/forking"

module Datadog
  module Tracing
    # {Datadog::Tracing::Context} is used to keep track of a the active trace for the current
    # execution flow. During each logical execution, the same {Datadog::Tracing::Context} is
    # used to represent a single logical trace, even if the trace is built
    # asynchronously.
    #
    # A single code execution may use multiple {Datadog::Tracing::Context} if part of the execution
    # must not be related to the current tracing. As example, a delayed job may
    # compose a standalone trace instead of being related to the same trace that
    # generates the job itself. On the other hand, if it's part of the same
    # {Datadog::Tracing::Context}, it will be related to the original trace.
    class Context
      include Core::Utils::Forking

      attr_reader \
        :active_trace

      def initialize(
        trace: nil
      )
        @active_trace = nil
        activate!(trace)
      end

      # Handles trace activation.
      #
      # Permits nil, allowing traces to be deactivated.
      #
      # If given a block, it will reset to the original
      # trace after the block completes.
      #
      # When restoring the original trace, if it is finished,
      # it will deactivate it. This prevents the context from
      # holding references to completed traces thereby releasing
      # its memory.
      def activate!(trace)
        if block_given?
          begin
            original_trace = @active_trace
            set_active_trace!(trace)
            yield
          ensure
            set_active_trace!(original_trace)
          end
        else
          set_active_trace!(trace)
        end
      end

      # Creates a copy of the context, when forked.
      def fork_clone
        forked_trace = @active_trace&.fork_clone
        self.class.new(trace: forked_trace)
      end

      private

      def set_active_trace!(trace)
        previous_trace = @active_trace

        # Don't retain finished traces
        @active_trace = (trace && !trace.finished?) ? trace : nil

        return @active_trace if previous_trace.equal?(@active_trace)

        if previous_trace
          previous_trace.send(:events).trace_deactivated.publish(previous_trace)
        end

        if @active_trace
          @active_trace.send(:events).trace_activated.publish(@active_trace)
        end

        @active_trace
      end
    end
  end
end
