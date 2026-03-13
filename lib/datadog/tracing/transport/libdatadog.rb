# frozen_string_literal: true

require_relative 'trace_formatter'

module Datadog
  module Tracing
    module Transport
      # Transport implementation backed by the Rust TraceExporter from libdatadog.
      #
      # This transport converts Ruby Span objects directly to Rust Span structs
      # and delegates serialization and sending to the Rust pipeline, which
      # handles stats computation, msgpack encoding, and HTTP transport with
      # retry logic.
      #
      # It implements the same +send_traces+ interface as
      # {Datadog::Tracing::Transport::Traces::Transport} so it can be used
      # as a drop-in replacement via the +Writer+'s +:transport+ option.
      #
      # @example Selecting the libdatadog transport in the Writer
      #   transport = Datadog::Tracing::Transport::Libdatadog::Transport.new(
      #     agent_settings: agent_settings,
      #     logger: Datadog.logger,
      #   )
      #   writer = Datadog::Tracing::Writer.new(transport: transport)
      #
      module Libdatadog
        NATIVE_UNSUPPORTED = begin
          require 'datadog/core'
          Datadog::Core::LIBDATADOG_API_FAILURE
        rescue StandardError => e
          e.message
        end

        def self.supported?
          NATIVE_UNSUPPORTED.nil?
        end

        # The native module and classes are defined by the C extension in
        # +ext/libdatadog_api/trace_exporter.c+ and become available after
        # +require 'libdatadog_api.<version>_<platform>'+.
        #
        # The hierarchy is:
        #   Datadog::Tracing::Transport::LibdatadogNative::TraceExporter
        #   Datadog::Tracing::Transport::LibdatadogNative::TracerSpan
        #   Datadog::Tracing::Transport::LibdatadogNative::Response

        class Transport
          attr_reader :logger

          # @param agent_settings [Datadog::Core::Configuration::AgentSettings]
          #   Agent connection settings (provides +#url+).
          # @param logger [Logger]
          def initialize(agent_settings:, logger: Datadog.logger)
            unless Libdatadog.supported?
              raise ArgumentError,
                "Libdatadog transport is not supported: #{NATIVE_UNSUPPORTED}"
            end

            @logger = logger

            url              = agent_settings.url
            tracer_version   = tracer_version_string
            language         = 'ruby'
            language_version = RUBY_VERSION
            language_interpreter = RUBY_ENGINE
            hostname         = Core::Environment::Socket.hostname rescue nil
            env              = Datadog.configuration.env
            service          = Datadog.configuration.service
            version          = Datadog.configuration.version

            @exporter = LibdatadogNative::TraceExporter._native_new(
              url,
              tracer_version,
              language,
              language_version,
              language_interpreter,
              hostname,
              env,
              service,
              version
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
            chunks = traces.map { |trace| trace.spans }

            @exporter._native_send_traces(chunks)
          rescue => e
            logger.debug("Libdatadog transport error: #{e.class} #{e.message}")
            [InternalErrorResponse.new(e)]
          end

          def stats
            @stats ||= Stats.new
          end

          private

          def tracer_version_string
            # Datadog::VERSION may not be loaded yet at require time,
            # so we access it lazily.
            if defined?(Datadog::VERSION::STRING)
              Datadog::VERSION::STRING
            else
              'unknown'
            end
          end
        end

        # Minimal response for internal errors (e.g. exceptions raised
        # before reaching the Rust transport).
        class InternalErrorResponse
          attr_reader :error

          def initialize(error)
            @error = error
          end

          def ok?;             false; end
          def internal_error?; true;  end
          def server_error?;   false; end
          def unsupported?;    false; end
          def not_found?;      false; end
          def client_error?;   false; end
          def payload;         nil;   end
          def trace_count;     0;     end

          def inspect
            "#<#{self.class} error=#{error.inspect}>"
          end
        end

        # Minimal stats tracker matching the interface used by Writer#stats.
        class Stats
          attr_accessor :success, :client_error, :server_error, :internal_error

          def initialize
            reset!
          end

          def reset!
            @success        = 0
            @client_error   = 0
            @server_error   = 0
            @internal_error = 0
            self
          end
        end
      end
    end
  end
end
