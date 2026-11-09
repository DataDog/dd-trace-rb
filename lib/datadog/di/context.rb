# frozen_string_literal: true

module Datadog
  module DI
    # Contains local and instance variables used when evaluating
    # expressions in DI Expression Language.
    #
    # @api private
    class Context
      # Initializes the context with the probe hit's state.
      #
      # @param probe [Datadog::DI::Probe] the probe whose hit is being
      #   evaluated
      # @param settings [Datadog::Core::Configuration::Settings] the current
      #   configuration settings
      # @param serializer [Datadog::DI::Serializer] the serializer for
      #   captured values
      # @param locals [Hash{Symbol => Object}, nil] local variables captured
      #   at the probe hit
      # @param target_self [Object, nil] the object the instrumented method
      #   runs on
      # @param path [String, nil] actual path of the instrumented file
      # @param caller_locations [Array<Thread::Backtrace::Location>, nil]
      #   stack frames captured at the probe hit
      # @param serialized_entry_args [Hash{Symbol => Object}, nil] entry
      #   arguments of the instrumented method, in serialized form
      # @param entry_capture_expressions [Hash{String => Object}, nil] entry
      #   capture expressions, in serialized form
      # @param entry_capture_evaluation_errors [Array<Datadog::DI::EvaluationFailure>, nil]
      #   failures from evaluating the entry capture expressions
      # @param admission_trace [Datadog::Tracing::TraceOperation, nil] the
      #   APM trace active when the sampling gate admitted the probe hit
      # @param admission_span [Datadog::Tracing::SpanOperation, nil] the APM
      #   span active when the sampling gate admitted the probe hit
      # @param return_value [Object, nil] the instrumented method's return
      #   value, for a method probe
      # @param duration [Float, nil] the instrumented method's execution
      #   time, in seconds, for a method probe
      # @param exception [Exception, nil] the exception raised by the
      #   instrumented method, for a method probe
      # @return [void]
      def initialize(probe:, settings:, serializer:, locals: nil,
        # In Ruby everything is a method, therefore we should always have
        # a target self. However, if we are not capturing a snapshot,
        # there is no need to pass in the target self.
        target_self: nil,
        path: nil, caller_locations: nil,
        serialized_entry_args: nil,
        entry_capture_expressions: nil,
        entry_capture_evaluation_errors: nil,
        admission_trace: nil,
        admission_span: nil,
        return_value: nil, duration: nil, exception: nil)
        @probe = probe
        @settings = settings
        @serializer = serializer
        @locals = locals
        @target_self = target_self
        @path = path
        @caller_locations = caller_locations
        @serialized_entry_args = serialized_entry_args
        @entry_capture_expressions = entry_capture_expressions
        @entry_capture_evaluation_errors = entry_capture_evaluation_errors
        @admission_trace = admission_trace
        @admission_span = admission_span
        @return_value = return_value
        @duration = duration
        @exception = exception
      end

      attr_reader :probe
      attr_reader :settings
      attr_reader :serializer
      attr_reader :locals
      attr_reader :target_self

      # Actual path of the instrumented file.
      attr_reader :path

      # TODO check how many stack frames we should be keeping/sending,
      # this should be all frames for enriched probes and no frames for
      # non-enriched probes?
      attr_reader :caller_locations

      attr_reader :serialized_entry_args

      attr_reader :entry_capture_expressions

      attr_reader :entry_capture_evaluation_errors

      # The APM trace active when the probe's hit was admitted by the
      # sampling gate, for a method probe; nil when the hit carried no
      # admission trace.
      #
      # @return [Datadog::Tracing::TraceOperation, nil]
      attr_reader :admission_trace

      # The APM span active when the probe's hit was admitted by the
      # sampling gate, for a method probe; nil when the hit carried no
      # admission span.
      #
      # @return [Datadog::Tracing::SpanOperation, nil]
      attr_reader :admission_span

      # Return value for the method, for a method probe
      attr_reader :return_value

      # How long the method took to execute, for a method probe
      attr_reader :duration

      # Exception raised by the method, if any, for a method probe
      attr_reader :exception

      # Returns the locals captured at the probe hit in serialized form,
      # or nil when no locals were captured.
      #
      # @param serialization_deadline [Float] absolute capture deadline in monotonic clock seconds
      # @return [Hash{Symbol => Hash}, nil] serialized locals keyed by variable name
      def serialized_locals(serialization_deadline:)
        # TODO cache?
        locals && serializer.serialize_vars(locals, deadline: serialization_deadline, **probe.snapshot_serializer_limits(settings))
      end

      def fetch(var_name)
        unless locals
          # TODO return "undefined" instead?
          return nil
        end
        locals[var_name.to_sym]
      end

      def fetch_ivar(var_name)
        target_self.instance_variable_get(var_name)
      end
    end
  end
end
