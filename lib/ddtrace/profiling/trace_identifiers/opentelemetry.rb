# frozen_string_literal: true

require 'ddtrace/utils/only_once'

module Datadog
  module Profiling
    module TraceIdentifiers
      # Used by Datadog::Profiling::TraceIdentifiers::Helper to get the trace identifiers (trace id and span id) for a
      # given thread, if there is an active trace for that thread in the OpenTelemetry library.
      #
      # This class MUST be safe to instantiate and call even when the opentelemetry-api library is not installed.
      class OpenTelemetry
        SUPPORTED_VERSIONS = Gem::Requirement.new('>= 0.17.0')
        private_constant :SUPPORTED_VERSIONS

        UNSUPPORTED_VERSION_ONLY_ONCE = Datadog::Utils::OnlyOnce.new
        private_constant :UNSUPPORTED_VERSION_ONLY_ONCE

        def initialize(**_)
          @available = false
          @checked_version = false
          @current_context_key = nil
        end

        def trace_identifiers_for(thread)
          return unless available?

          current_context = Array(thread[@current_context_key]).last # <= 1.0.0.rc1 single value; > 1.0.0.rc1 array
          return unless current_context

          span = ::OpenTelemetry::Trace.current_span(current_context)

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
          return false unless defined?(::OpenTelemetry)

          unless @checked_version
            # Because the profiler can start quite early in the application boot process, it's possible for us to
            # observe the OpenTelemetry module, but still be in a situation where the full opentelemetry gem has not
            # finished being require'd.
            #
            # To solve this, we use a require which forces a synchronization point -- this require will not return
            # until the gem is fully loaded.
            require 'opentelemetry-api'
            @available = supported?
            @checked_version = true
          end

          @available
        end

        def binary_8_byte_string_to_i(string)
          string.unpack1('Q>')
        end

        def trace_id_to_datadog(trace_id)
          # Datadog converts opentelemetry 16 byte / 128 bit ids to 8 byte / 64 bit ids by dropping the leading 8 bytes,
          # see also
          # * https://github.com/DataDog/dd-trace-rb/blob/e63e65f19887d011cd957f7e58361f4af0df2050/lib/ddtrace/distributed_tracing/headers/helpers.rb#L28-L31
          # * https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/9c7c329f0877f72befb36c61c47899d5a4525037/exporter/datadogexporter/translate_traces.go#L469
          # * https://github.com/open-telemetry/opentelemetry-specification/issues/525
          trace_id[8..16]
        end

        def supported?
          unless defined?(::OpenTelemetry::VERSION) &&
                 SUPPORTED_VERSIONS.satisfied_by?(Gem::Version.new(::OpenTelemetry::VERSION))
            UNSUPPORTED_VERSION_ONLY_ONCE.run do
              Datadog.logger.warn(
                'Profiler: Incompatible version of opentelemetry-api detected; ' \
                "ensure you have opentelemetry-api #{SUPPORTED_VERSIONS} by adding " \
                "`gem 'opentelemetry-api', '#{SUPPORTED_VERSIONS}'` to your Gemfile or gems.rb file. " \
                'Linking of OpenTelemetry traces to profiles will not be available. '
              )
            end

            return false
          end

          key = retrieve_current_context_key
          return false unless key

          @current_context_key = key
          true
        end

        def retrieve_current_context_key
          if defined?(::OpenTelemetry::Context::KEY) # <= 1.0.0.rc1
            ::OpenTelemetry::Context::KEY
          elsif ::OpenTelemetry::Context.const_defined?(:STACK_KEY)
            ::OpenTelemetry::Context.const_get(:STACK_KEY)
          end
        end
      end
    end
  end
end
