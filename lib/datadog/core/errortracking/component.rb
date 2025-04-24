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
        attr_accessor :tracepoint,
          :tracer,
          :to_instrument_modules,
          :instrumented_files,
          :script_compiled_tracepoint

        def self.build(settings, tracer)
          return if settings.errortracking.to_instrument.empty? && settings.errortracking.to_instrument_modules.empty?
          return if !settings.errortracking.to_instrument.empty? &&
            !['all', 'user', 'third_party'].include?(settings.errortracking.to_instrument)

          new(
            tracer: tracer,
            to_instrument: settings.errortracking.to_instrument,
            to_instrument_modules: settings.errortracking.to_instrument_modules,
          ).tap(&:start)
        end

        def initialize(tracer:, to_instrument:, to_instrument_modules:)
          @tracer = tracer
          @instrumented_files = {} unless to_instrument_modules.empty?
          @to_instrument_modules = to_instrument_modules

          # Filter function is used to filter out the exception
          # we do not want to report. For instance exception from third
          # party packages.
          @filter_function = Filters.generate_filter(to_instrument, @instrumented_files)

          # :raise event was added in Ruby 3.3
          #
          # Before Ruby3.3 the tracepoint listen for :raise events.
          # If an error is not handled, we will delete the according
          # span event in the collector.
          event = RUBY_VERSION >= '3.3' ? :rescue : :raise
          @tracepoint = TracePoint.new(event) do |tp|
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

          # Initialize the script_compiled TracePoint to track loaded files
          # This replaces the Kernel monkey patching approach
          @script_compiled_tracepoint = TracePoint.new(:script_compiled) do |tp|
            next if tp.eval_script

            path = tp.instruction_sequence.path
            next unless path

            @to_instrument_modules.each do |module_to_instr|
              # puts "#{module_to_instr} vs #{path} vs #{path.match?(%r{/#{Regexp.escape(module_to_instr)}(?=/|\.rb)})}"
              add_instrumented_file(path) if path.match?(%r{/#{Regexp.escape(module_to_instr)}(?=/|\.rb)})
            end
          end
        end

        # Starts the tracepoints.
        #
        # Enables the script_compiled tracepoint if to_instrument_modules is not empty.
        def start
          @tracepoint.enable
          @script_compiled_tracepoint.enable unless @to_instrument_modules.empty?
        end

        # Shuts down error tracker.
        #
        # Disables the tracepoints.
        def shutdown!
          @tracepoint.disable
          @script_compiled_tracepoint&.disable
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
