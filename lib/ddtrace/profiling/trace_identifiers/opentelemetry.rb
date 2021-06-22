# frozen_string_literal: true

module Datadog
  module Profiling
    module TraceIdentifiers
      class OpenTelemetry
        def initialize
          @available = false
        end

        def trace_identifiers_for(thread)
          return unless available?

          span = ::OpenTelemetry::Trace.current_span(thread[::OpenTelemetry::Context::KEY])

          if span && span != ::OpenTelemetry::Trace::Span::INVALID
            context = span.context
            [
              binary_8_byte_string_to_i(trace_id_to_datadog(context.trace_id)),
              binary_8_byte_string_to_i(context.span_id)
            ]
          end
        end

        private

        def available?
          return true if @available

          if defined?(::OpenTelemetry)
            # Because the profiler can start quite early in the application boot process, it's possible for us to
            # observe the OpenTelemetry module, but still be in a situation where the full opentelemetry gem has not
            # finished being require'd.
            #
            # To solve this, we use a require which forces a synchronization point -- this require will not return
            # until the gem is fully loaded.
            require 'opentelemetry-api'
            @available = true
          end

          @available
        end

        def binary_8_byte_string_to_i(string)
          string.unpack1("Q>")
        end

        def trace_id_to_datadog(trace_id)
          # Datadog converts opentelemetry 16 byte / 128 bit ids to 8 byte / 64 bit ids by dropping the leading 8 bytes,
          # see also
          # * https://github.com/DataDog/dd-trace-rb/blob/e63e65f19887d011cd957f7e58361f4af0df2050/lib/ddtrace/distributed_tracing/headers/helpers.rb#L28-L31
          # * https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/9c7c329f0877f72befb36c61c47899d5a4525037/exporter/datadogexporter/translate_traces.go#L469
          # * https://github.com/open-telemetry/opentelemetry-specification/issues/525
          trace_id[8..16]
        end
      end
    end
  end
end
