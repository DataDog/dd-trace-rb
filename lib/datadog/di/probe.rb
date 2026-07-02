# frozen_string_literal: true

require_relative "error"
require_relative "utils"
require_relative "../core/rate_limiter"

module Datadog
  module DI
    # Encapsulates probe information (as received via remote config)
    # and state (e.g. whether the probe was installed, or executed).
    #
    # It is possible that remote configuration will specify an unsupported
    # probe type or attribute, due to new DI functionality being added
    # over time. We want to have predictable behavior in such cases, and
    # since we can't guarantee that there will be enough information in
    # a remote config payload to construct a functional probe, ProbeBuilder
    # and remote config code must be prepared to deal with exceptions
    # raised by Probe constructor in particular. Therefore, Probe constructor
    # will raise an exception if it determines that there is not enough
    # information (or conflicting information) in the arguments to create a
    # functional probe, and upstream code is tasked with not spamming logs
    # with notifications of such errors (and potentially limiting the
    # attempts to construct probe from a given payload).
    #
    # Note that, while remote configuration provides line numbers as an
    # array, the only supported line number configuration is a single line
    # (this is the case for all languages currently). Therefore Probe
    # only supports one line number, and ProbeBuilder is responsible for
    # extracting that one line number out of the array received from RC.
    #
    # Note: only some of the parameter/attribute values are currently validated.
    #
    # @api private
    class Probe
      KNOWN_TYPES = %i[log].freeze

      # Permitted values for the +evaluate_at+ constructor argument.
      # +:exit+ is the default applied when +nil+ is passed (this matches the
      # libdatadog ProbeCommon JSON-parse default of EvaluateAt::Exit, which
      # PHP shares; Python's Snapshot._timing also resolves DEFAULT to EXIT
      # for log probes).
      EVALUATE_AT_VALUES = %i[entry exit].freeze

      def initialize(id:, type:,
        file: nil, line_no: nil, type_name: nil, method_name: nil,
        template: nil, template_segments: nil,
        capture_snapshot: false, max_capture_depth: nil,
        max_capture_attribute_count: nil,
        max_capture_collection_size: nil, max_capture_string_length: nil,
        capture_expressions: [],
        evaluate_at: nil,
        condition: nil,
        rate_limit: nil)
        # Perform some sanity checks here to detect unexpected attribute
        # combinations, in order to not do them in subsequent code.
        unless KNOWN_TYPES.include?(type)
          raise ArgumentError, "Unknown probe type: #{type}"
        end

        # Probe should be inferred to be a line probe if the specification
        # contains a line number. This how Java tracer works and Go tracer
        # is implementing the same behavior, and Go will have all 3 fields
        # (file path, line number and method name) for line probes.
        # Do not raise if line number and method name both exist - instead
        # treat the probe as a line probe.
        #
        # In the future we want to provide type name and method name to line
        # probes, so that the library can verify that the instrumented line
        # is in the method that the frontend showed to the user when the
        # user created the probe.

        if line_no && !file
          raise ArgumentError, "Probe contains line number but not file: #{id}"
        end

        if type_name && !method_name || method_name && !type_name
          raise ArgumentError, "Partial method probe definition: #{id}"
        end

        if line_no.nil? && method_name.nil?
          raise ArgumentError, "Unhandled probe type: neither method nor line probe: #{id}"
        end

        @id = id
        @type = type
        @file = file
        @line_no = line_no
        @type_name = type_name
        @method_name = method_name
        @template = template
        @template_segments = template_segments
        @capture_snapshot = !!capture_snapshot
        @max_capture_depth = max_capture_depth
        @max_capture_attribute_count = max_capture_attribute_count
        @max_capture_collection_size = max_capture_collection_size
        @max_capture_string_length = max_capture_string_length
        @capture_expressions = capture_expressions || []
        # Per-expression evaluation timing on method probes. nil from the
        # RC payload (or the constructor default) coerces to +:exit+, matching
        # the libdatadog ProbeCommon JSON-parse default (EvaluateAt::Exit).
        # Unknown symbols are rejected at construction. Line probes ignore
        # this value (single firing point at the TracePoint callback).
        evaluate_at = :exit if evaluate_at.nil?
        unless EVALUATE_AT_VALUES.include?(evaluate_at)
          raise ArgumentError, "Unknown evaluate_at value: #{evaluate_at.inspect} (expected one of #{EVALUATE_AT_VALUES.inspect})"
        end
        @evaluate_at = evaluate_at
        @condition = condition

        # Capture-expression probes are charged against the snapshot rate-limit
        # bucket (1/sec default), matching Python/.NET/Go DI. They are not
        # treated as cheap log probes (5000/sec) because evaluating arbitrary
        # user-authored expressions has snapshot-class cost.
        @rate_limit = rate_limit || ((@capture_snapshot || !@capture_expressions.empty?) ? 1 : 5000)
        @rate_limiter = Datadog::Core::TokenBucket.new(@rate_limit)

        # At most one report per second.
        # We create the rate limiter here even though it may never be used,
        # to avoid having to synchronize the creation since method probes
        # can be executed on multiple threads concurrently (even if line
        # probes are never executed concurrently since those are done in a
        # trace point).
        if condition
          @condition_evaluation_failed_rate_limiter = Datadog::Core::TokenBucket.new(1)
        end

        @emitting_notified = false
        @enabled = true
      end

      attr_reader :id
      attr_reader :type
      attr_reader :file
      attr_reader :line_no
      attr_reader :type_name
      attr_reader :method_name
      attr_reader :template
      attr_reader :template_segments

      # The compiled condition for the probe, as a String.
      attr_reader :condition

      # Configured maximum capture depth. Can be nil in which case
      # the global default will be used.
      attr_reader :max_capture_depth

      # Configured maximum capture attribute count. Can be nil in which case
      # the global default will be used.
      attr_reader :max_capture_attribute_count

      # Configured maximum collection size. Can be nil in which case the
      # global default will be used.
      attr_reader :max_capture_collection_size

      # Configured maximum string length. Can be nil in which case the
      # global default will be used.
      attr_reader :max_capture_string_length

      # Capture expressions attached to this probe. Empty array when no
      # capture expressions are configured.
      #
      # @return [Array<Datadog::DI::CaptureExpression>]
      attr_reader :capture_expressions

      # Per-expression evaluation timing for method probes. One of
      # +:entry+ / +:exit+. Defaults to +:exit+ (matching libdatadog's
      # ProbeCommon JSON-parse default). Ignored by line probes.
      #
      # @return [Symbol]
      attr_reader :evaluate_at

      # Rate limit in effect, in invocations per second. Always present.
      attr_reader :rate_limit

      # Rate limiter object. For internal DI use only.
      attr_reader :rate_limiter

      # Rate limiter object for sending snapshots with evaluation errors
      # for when probe condition evaluation fails.
      # This rate limit is separate from the "base" rate limit for the probe
      # because when the condition evaluation succeeds we want the "base"
      # rate limit applied, not tainted by any evaluation errors
      # (for example, the condition can be highly selective, and when it
      # does not hold the evaluation may fail - we don't want to use up the
      # probe rate limit for the errors).
      attr_reader :condition_evaluation_failed_rate_limiter

      def capture_snapshot?
        @capture_snapshot
      end

      # Returns whether the probe has any capture expressions configured.
      def capture_expressions?
        !@capture_expressions.empty?
      end

      # Returns the four capture-limit keyword arguments for snapshot
      # serialization, applying the probe-level override for each field and
      # falling back to the DI settings default when the probe-level value
      # is nil. The result is intended to be splatted into
      # +Serializer#serialize_value+, +serialize_args+, or +serialize_vars+.
      #
      # @param settings [Datadog::Core::Configuration::Settings] tracer settings
      #   providing the dynamic_instrumentation.max_capture_* fallback values.
      # @return [Hash{Symbol => Integer}] hash with keys :depth, :attribute_count,
      #   :length, :collection_size -- all values are Integers (no nils).
      def snapshot_serializer_limits(settings)
        di = settings.dynamic_instrumentation
        {
          depth: max_capture_depth || di.max_capture_depth,
          attribute_count: max_capture_attribute_count || di.max_capture_attribute_count,
          length: max_capture_string_length || di.max_capture_string_length,
          collection_size: max_capture_collection_size || di.max_capture_collection_size,
        }
      end

      # Returns whether the probe is a line probe.
      #
      # Method probes may still specify a file name (to aid in locating the
      # method or for stack traversal purposes?), therefore we do not check
      # for file name/path presence here and just consider the line number.
      def line?
        # Constructor checks that file is given if line number is given,
        # but for safety, check again here since we somehow got a probe with
        # a line number but no file in the wild.
        !!(file && line_no)
      end

      # Returns whether the probe is a method probe.
      def method?
        line_no.nil?
      end

      # Returns the line number associated with the probe, raising
      # Error::MissingLineNumber if the probe does not have a line number
      # associated with it.
      #
      # This method is used by instrumentation driver to ensure a line number
      # that is passed into the instrumentation logic is actually a line number
      # and not nil.
      def line_no!
        if line_no.nil?
          raise Error::MissingLineNumber, "Probe #{id} does not have a line number associated with it"
        end
        line_no
      end

      # Returns the method name associated with the probe, raising
      # Error::MissingMethodName if the probe does not have a method name
      # associated with it.
      #
      # This method is used by instrumentation driver to ensure a method name
      # that is passed into the instrumentation logic is actually a method name
      # and not nil.
      def method_name!
        if method_name.nil?
          raise Error::MissingMethodName, "Probe #{id} does not have a method name associated with it"
        end
        method_name
      end

      # Source code location of the probe, for diagnostic reporting.
      def location
        if method?
          "#{type_name}.#{method_name}"
        elsif line?
          "#{file}:#{line_no}"
        else
          # This case should not be possible because constructor verifies that
          # the probe is a method or a line probe.
          raise NotImplementedError
        end
      end

      # Returns whether the provided +path+ matches the user-designated
      # file (of a line probe).
      #
      # Delegates to Utils.path_can_match_spec? which performs fuzzy
      # matching. See the comments in utils.rb for details.
      def file_matches?(path)
        if path.nil?
          raise ArgumentError, "Cannot match against a nil path"
        end
        unless file
          raise ArgumentError, "Probe does not have a file to match against"
        end
        Utils.path_can_match_spec?(path, file)
      end

      # Instrumentation module for method probes.
      attr_accessor :instrumentation_module

      # Line trace point for line probes. Normally this would be a targeted
      # trace point.
      attr_accessor :instrumentation_trace_point

      # Actual path to the file instrumented by the probe, for line probes,
      # when code tracking is available and line trace point is targeted.
      # For untargeted line trace points instrumented path will be nil.
      attr_accessor :instrumented_path

      # TODO emitting_notified reads and writes should in theory be locked,
      # however since DI is only implemented for MRI in practice the missing
      # locking should not cause issues.
      attr_writer :emitting_notified
      def emitting_notified?
        !!@emitting_notified
      end

      def executed_on_line?
        !!(defined?(@executed_on_line) && @executed_on_line)
      end

      def executed_on_line!
        # TODO lock?
        @executed_on_line = true
      end

      def enabled?
        @enabled
      end

      def disable!
        @enabled = false
      end
    end
  end
end
