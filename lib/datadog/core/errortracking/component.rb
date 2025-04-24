# frozen_string_literal: true

require_relative 'collector'
require_relative 'filters'

module Datadog
  module Core
    module Errortracking
      # Component for error tracking.
      #
      # Only one instance of the Component should ever be active.
      #
      # The component instance records every handled exceptions from the configured scopes
      # (user, third_party packages, specified modules of everything). T
      class Component
        attr_accessor :handled_exc_tracker,
          :module_path_getter,
          :tracer,
          :modules_to_instrument,
          :instrumented_files,
          def self.build(settings, tracer)
            if settings.errortracking.instrumentation_scope.empty? && settings.errortracking.modules_to_instrument.empty?
              return
            end
            return if !settings.errortracking.instrumentation_scope.empty? &&
              !['all', 'user', 'third_party'].include?(settings.errortracking.instrumentation_scope)

            new(
              tracer: tracer,
              instrumentation_scope: settings.errortracking.instrumentation_scope,
              modules_to_instrument: settings.errortracking.modules_to_instrument,
            ).tap(&:start)
          end

        def initialize(tracer:, instrumentation_scope:, modules_to_instrument:)
          @tracer = tracer
          # Hash containing the file path of the modules to instrument
          @instrumented_files = {} unless modules_to_instrument.empty?
          @modules_to_instrument = modules_to_instrument

          # Filter function is used to filter out the exception
          # we do not want to report. For instance exception from third
          # party packages.
          @filter_function = Filters.generate_filter(instrumentation_scope, @instrumented_files)

          # :raise event was added in Ruby 3.3
          #
          # Before Ruby3.3 the tracepoint listen for :raise events.
          # If an error is not handled, we will delete the according
          # span event in the collector.
          event = RUBY_VERSION >= '3.3' ? :rescue : :raise

          # This tracepoint is in charge of capturing the handled exceptions
          # and of adding the corresponding span events to the collector
          @handled_exc_tracker = TracePoint.new(event) do |tp|
            active_span = @tracer.active_span
            unless active_span.nil?
              raised_exception = tp.raised_exception
              rescue_file_path = tp.path
              if @filter_function.call(rescue_file_path)
                span_event = _generate_span_event(raised_exception)
                active_span.collector.add_span_event(active_span, raised_exception, span_event)
              end
            end
          end

          # The only thing we know about the handled errors is in which file it was
          # rescued. Therefore, when a user specifies the modules to instrument,
          # we use this tracepoint to get their paths.
          unless @modules_to_instrument.empty?
            @module_path_getter = TracePoint.new(:script_compiled) do |tp|
              next if tp.eval_script

              path = tp.instruction_sequence.path
              next if path.nil?

              @modules_to_instrument.each do |module_to_instr|
                # The regex is looking for the name of the module with '/' before
                # and either '/' or '.rb' after
                add_instrumented_file(path) if path.match?(%r{/#{Regexp.escape(module_to_instr)}(?=/|\.rb)})
              end
            end
          end
        end

        # Starts the tracepoints.
        #
        # Enables the script_compiled tracepoint if modules_to_instrument is not empty.
        def start
          @handled_exc_tracker.enable
          @module_path_getter&.enable
        end

        # Shuts down error tracker.
        #
        # Disables the tracepoints.
        def shutdown!
          @handled_exc_tracker.disable
          @module_path_getter&.disable
        end

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

        def add_instrumented_file(file_path)
          @instrumented_files[file_path] = true
        end
      end
    end
  end
end
