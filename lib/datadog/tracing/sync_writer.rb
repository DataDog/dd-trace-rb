# frozen_string_literal: true

require_relative 'pipeline'
require_relative 'runtime/metrics'
require_relative 'writer'

require_relative 'transport/http'

module Datadog
  module Tracing
    # SyncWriter flushes both services and traces synchronously
    #
    # Note: If you're wondering if this class is used at all, since there are no other references to it on the codebase,
    # the separate `datadog-lambda` uses it as of February 2021:
    # <https://github.com/DataDog/datadog-lambda-rb/blob/c15f0f0916c90123416dc44e7d6800ef4a7cfdbf/lib/datadog/lambda.rb#L38>
    # @public_api
    class SyncWriter
      attr_reader \
        :logger,
        :events,
        :transport,
        :agent_settings

      # @param [Datadog::Tracing::Transport::Traces::Transport] transport a custom transport instance.
      #   If provided, overrides `transport_options` and `agent_settings`.
      # @param [Hash<Symbol,Object>] transport_options options for the default transport instance.
      # @param [Datadog::Tracing::Configuration::AgentSettings] agent_settings agent options for
      #   the default transport instance.
      def initialize(transport: nil, transport_options: {}, agent_settings: nil, logger: Datadog.logger)
        @logger = logger
        @agent_settings = agent_settings

        @transport = transport || begin
          Transport::HTTP.default(agent_settings: agent_settings, logger: logger, **transport_options)
        end

        @events = Writer::Events.new
      end

      # Sends traces to the configured transport.
      #
      # Traces are flushed immediately.
      def write(trace)
        flush_trace(trace)
      rescue => e
        logger.debug(e)
      end

      # Stops the {SyncWriter}.
      # The {SyncWriter} holds no worker thread, but it owns its transport, so
      # on teardown we deterministically release transports that hold native
      # resources (e.g. the native trace exporter's Rust runtime and
      # process-global fork hooks) rather than relying on the GC finalizer.
      # The default HTTP transport has no `#close` and is left untouched, and
      # `#close` is idempotent so repeated `#stop` calls are safe.
      def stop
        @transport.close if @transport.respond_to?(:close)
        true
      end

      private

      def flush_trace(trace)
        processed_traces = Pipeline.process!([trace])
        return if processed_traces.empty?

        responses = transport.send_traces(processed_traces)

        events.after_send.publish(self, responses)

        responses
      end
    end
  end
end
