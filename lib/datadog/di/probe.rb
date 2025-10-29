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

      def initialize(id:, type:,
        file: nil, line_no: nil, type_name: nil, method_name: nil,
        template: nil, template_segments: nil,
        capture_snapshot: false, max_capture_depth: nil,
        max_capture_attribute_count: nil, condition: nil,
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
        @condition = condition

        @rate_limit = rate_limit || (@capture_snapshot ? 1 : 5000)
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
        !!@executed_on_line
      end

      def executed_on_line!
        # TODO lock?
        @executed_on_line = true
      end
    end
  end
end
