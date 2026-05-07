# frozen_string_literal: true

require_relative 'trace_formatter'
require_relative 'statistics'

module Datadog
  module Tracing
    module Transport
      # Transport backed by the native trace exporter (Rust via C FFI).
      #
      # Converts Ruby Span objects directly to Rust spans and delegates
      # serialization and sending to the Rust data pipeline, which handles
      # stats computation, msgpack encoding, and HTTP transport with retry
      # logic.
      #
      # Implements the same +send_traces+ / +stats+ interface as
      # {Datadog::Tracing::Transport::Traces::Transport} so it can be used
      # as a drop-in replacement via the +Writer+'s +:transport+ option.
      module Native
        # Returns +nil+ when the native extension is available, or a +String+
        # describing why it is not.
        UNSUPPORTED_REASON = begin
          require 'datadog/core'
          Datadog::Core::LIBDATADOG_API_FAILURE
        rescue StandardError => e
          e.message
        end

        def self.supported?
          UNSUPPORTED_REASON.nil?
        end

        # The native module and classes are defined by the C extension in
        # +ext/libdatadog_api/trace_exporter.c+ and become available after
        # the native extension is loaded.
        #
        # The hierarchy is:
        #   Datadog::Tracing::Transport::Native::TraceExporter
        #   Datadog::Tracing::Transport::Native::TracerSpan
        #   Datadog::Tracing::Transport::Native::Response

        # Drop-in transport that delegates to the native trace exporter.
        class Transport
          include Statistics

          attr_reader :logger

          # @param agent_settings [Datadog::Core::Configuration::AgentSettingsResolver::AgentSettings]
          #   Agent connection settings (provides +#url+).
          # @param logger [Logger]
          def initialize(agent_settings:, logger: Datadog.logger)
            unless Native.supported?
              raise "Native transport is not supported: #{UNSUPPORTED_REASON}"
            end

            @logger = logger

            url                  = agent_settings.url
            tracer_version       = tracer_version_string
            language             = Core::Environment::Ext::LANG
            language_version     = Core::Environment::Ext::LANG_VERSION
            language_interpreter = Core::Environment::Ext::LANG_INTERPRETER
            hostname             = Core::Environment::Socket.hostname rescue nil
            env                  = Datadog.configuration.env
            service              = Datadog.configuration.service
            version              = Datadog.configuration.version

            @exporter = Native::TraceExporter._native_new(
              url: url,
              tracer_version: tracer_version,
              language: language,
              language_version: language_version,
              language_interpreter: language_interpreter,
              hostname: hostname,
              env: env,
              service: service,
              version: version
            )
          end

          # Send a list of traces to the agent.
          #
          # Each trace is a {Datadog::Tracing::TraceSegment} whose +#spans+
          # returns an +Array+ of {Datadog::Tracing::Span}.
          #
          # @param traces [Array<Datadog::Tracing::TraceSegment>]
          # @return [Array<Response>] one response per batch sent
          def send_traces(traces)
            return [] if traces.empty?

            # Apply trace-level tags to root spans (same as the HTTP transport)
            traces.each { |trace| TraceFormatter.format!(trace) }

            # Build the Array<Array<Span>> structure expected by the C extension.
            # Each trace segment becomes one inner array (one trace chunk).
            chunks = traces.map(&:spans)

            responses = @exporter._native_send_traces(chunks)

            # Update statistics from the response
            responses.each { |response| update_stats_from_response!(response) }

            responses
          rescue => e
            logger.debug { "Native transport error: #{e.class.name} #{e.message}" }
            update_stats_from_exception!(e)
            [InternalErrorResponse.new(e)]
          end

          private

          def tracer_version_string
            defined?(Datadog::VERSION::STRING) ? Datadog::VERSION::STRING : 'unknown'
          end
        end

        # Response for internal errors (exceptions raised before reaching
        # the native transport).
        class InternalErrorResponse
          attr_reader :error

          def initialize(error)
            @error = error
          end

          def ok?;             false; end
          def internal_error?; true;  end
          def server_error?;   false; end
          def client_error?;   false; end
          def not_found?;      false; end
          def unsupported?;    false; end
          def payload;         nil;   end
          def trace_count;     0;     end

          def inspect
            "#<#{self.class} error=#{error.inspect}>"
          end
        end
      end
    end
  end
end
