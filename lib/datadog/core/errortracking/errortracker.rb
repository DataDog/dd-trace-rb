require_relative 'collector'
require_relative 'filters'

module Datadog
  module Core
    module Errortracking
      class ErrorTracker
        attr_accessor :tracepoint, :tracer, :collector, :instrumented_files
        def initialize(tracer, to_instrument, to_instrument_modules)
          @tracer = tracer
          @collector = Collector.new

          if to_instrument_modules.length > 0
            @instrumented_files = {}
          end
          @filter_function = Filters::generate_filter(to_instrument, instrumented_files)

          event = RUBY_VERSION >= '3.3' ? :rescue : :raise
          @tracepoint = TracePoint.new(event) do |tp|
            active_span = @tracer.active_span
            unless active_span.nil?
              raised_exception = tp.raised_exception
              rescue_file_path = tp.path

              if @filter_function.call(rescue_file_path)
                span_event = _generate_span_event(raised_exception)
                @collector.add_span_event(active_span, raised_exception, span_event)
              end
            end
          end
        end

        def _generate_span_event(exception)
          formatted_exception = Datadog::Core::Error::build_from(exception)
          attributes = {
            'exception.type' => formatted_exception.type,
            'exception.message' => formatted_exception.message,
            'exception.stacktrace' => formatted_exception.backtrace
          }
          Datadog::Tracing::SpanEvent.new('exception', attributes: attributes)
        end

        def start()
          @tracepoint.enable
        end

        def stop()
          @tracepoint.disable
        end

        def add_instrumented_file(file_path)
          @instrumented_files[file_path] = true
        end
      end
    end
  end
end