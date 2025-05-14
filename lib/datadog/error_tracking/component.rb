# frozen_string_literal: true

require 'set'
require_relative 'collector'
require_relative 'filters'

module Datadog
  module ErrorTracking
    # Component for Error Tracking.
    #
    # Only one instance of the Component should ever be active.
    #
    # The component instance records every handled exceptions from the configured scopes
    # (user, third_party packages, specified files or everything).
    class Component
      LOCK = Mutex.new

      attr_accessor :handled_exc_tracker,
        :module_path_getter,
        :tracer,
        :handled_errors_include,
        :instrumented_files

      class << self
        def build(settings, tracer, logger)
          return if !settings.respond_to?(:error_tracking) || (settings.error_tracking.handled_errors.nil? &&
            settings.error_tracking.handled_errors_include.empty?)

          return unless environment_supported?(logger)

          new(
            tracer: tracer,
            handled_errors: settings.error_tracking.handled_errors,
            handled_errors_include: settings.error_tracking.handled_errors_include,
          ).tap(&:start)
        end

        # Checks whether the runtime environment is supported by
        # error tracking.
        def environment_supported?(logger)
          if RUBY_ENGINE != 'ruby'
            logger.warn("error tracking: cannot enable error tracking: MRI is required, but running on #{RUBY_ENGINE}")
            return false
          end
          if RUBY_VERSION < '2.6'
            logger.warn(
              "error tracking: cannot enable error tracking: Ruby 2.6+ is required, but running
              on #{RUBY_VERSION}"
            )
            return false
          end
          true
        end
      end

      def initialize(tracer:, handled_errors:, handled_errors_include:)
        @tracer = tracer

        # Hash containing the file path of the modules to instrument
        @instrumented_files = Set.new unless handled_errors_include.empty?
        @handled_errors_include = handled_errors_include

        # Filter function is used to filter out the exception
        # we do not want to report. For instance exception from gems.
        @filter_function = Filters.generate_filter(handled_errors, @instrumented_files)

        # :rescue event was added in Ruby 3.3
        #
        # Before Ruby3.3 the tracepoint listen for :raise events.
        # If an error is not handled, we will delete the according
        # span event in the collector.
        event = RUBY_VERSION >= '3.3' ? :rescue : :raise

        # This tracepoint is in charge of capturing the handled exceptions
        # and of adding the corresponding span events to the collector
        @handled_exc_tracker = create_exc_tracker_tracepoint(event)

        unless @instrumented_files.nil?
          # The only thing we know about the handled errors is the path of the file
          # in which the error was rescued. Therefore, we need to retrieve the path
          # of the files the user want to instrument. This tracepoint is used for that
          # purpose
          @include_path_getter = create_script_compiled_tracepoint
        end
      end

      def create_exc_tracker_tracepoint(event)
        TracePoint.new(event) do |tp|
          active_span = @tracer.active_span
          unless active_span.nil?
            raised_exception = tp.raised_exception
            # Note that in 3.2, this will give the path of where the error was raised
            # which may cause de handled_error_include env variable to malfunction.
            rescue_file_path = tp.path
            if @filter_function.call(rescue_file_path)
              span_event = _generate_span_event(raised_exception)
              LOCK.synchronize do
                collector = active_span.collector { Collector.new }
                collector.add_span_event(active_span, raised_exception, span_event)
              end
            end
          end
        end
      end

      def create_script_compiled_tracepoint
        TracePoint.new(:script_compiled) do |tp|
          next if tp.eval_script

          path = tp.instruction_sequence.path
          next if path.nil?

          @handled_errors_include.each do |file_to_instr|
            # The user can provide either
            # - absolute_path starting with '/'. In that case the path of the file
            #   should begin with file_to_instr
            # - a relative_path starting with './'. In that case, we extend the path
            #   and it is the same as above
            # - otherwise we just check if the name provided is in the path and is
            #   either the name of a folder or of a ruby file.
            regex =
              if file_to_instr.start_with?('/')
                %r{\A#{Regexp.escape(file_to_instr)}(?:/|\.rb\z|\z)}
              elsif file_to_instr.start_with?('./')
                abs_path = File.expand_path(file_to_instr)
                %r{\A#{Regexp.escape(abs_path)}(?:/|\.rb\z|\z)}
              else
                %r{/#{Regexp.escape(file_to_instr)}(?:/|\.rb\z|\z)}
              end

            _add_instrumented_file(path) if path.match?(regex)
          end
        end
      end

      # Starts the tracepoints.
      #
      # Enables the script_compiled tracepoint if handled_errors_include is not empty.
      def start
        @handled_exc_tracker.enable
        @include_path_getter&.enable
      end

      # Shuts down error tracker.
      #
      # Disables the tracepoints.
      def shutdown!
        @handled_exc_tracker.disable
        @include_path_getter&.disable
      end

      private

      # Generates a span event from the exception info.
      #
      # The event follows the otel semantics.
      # https://opentelemetry.io/docs/specs/otel/trace/exceptions/
      def _generate_span_event(exception)
        formatted_exception = Datadog::Core::Error.build_from(exception)
        attributes = {
          'exception.type' => formatted_exception.type,
          'exception.message' => formatted_exception.message,
          'exception.stacktrace' => formatted_exception.backtrace
        }
        Datadog::Tracing::SpanEvent.new('exception', attributes: attributes)
      end

      def _add_instrumented_file(file_path)
        @instrumented_files&.add(file_path)
      end
    end
  end
end
