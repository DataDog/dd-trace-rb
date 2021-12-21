# typed: true
require 'ddtrace/pipeline'
require 'ddtrace/runtime/metrics'
require 'ddtrace/utils/only_once'
require 'ddtrace/writer'

module Datadog
  # SyncWriter flushes both services and traces synchronously
  # DEV: To be replaced by Datadog::Workers::TraceWriter.
  #
  # Note: If you're wondering if this class is used at all, since there are no other references to it on the codebase,
  # the separate `datadog-lambda` uses it as of February 2021:
  # <https://github.com/DataDog/datadog-lambda-rb/blob/c15f0f0916c90123416dc44e7d6800ef4a7cfdbf/lib/datadog/lambda.rb#L38>
  class SyncWriter
    attr_reader \
      :events,
      :transport

    # @param [Datadog::Transport::Traces::Transport] transport a custom transport instance.
    #   If provided, overrides `transport_options` and `agent_settings`.
    # @param [Hash<Symbol,Object>] transport_options options for the default transport instance.
    # @param [Datadog::Configuration::AgentSettingsResolver::AgentSettings] agent_settings agent options for
    #   the default transport instance.
    # @public_api
    def initialize(transport: nil, transport_options: {}, agent_settings: nil)
      @transport = transport || begin
        transport_options[:agent_settings] = agent_settings if agent_settings
        Transport::HTTP.default(**transport_options)
      end

      @events = Writer::Events.new
    end

    # Sends traces to the configured transport.
    #
    # Traces are flushed immediately.
    #
    # @public_api
    def write(trace)
      flush_trace(trace)
    rescue => e
      Datadog.logger.debug(e)
    end

    # Does nothing.
    # The {SyncWriter} does not need to be stopped as it holds no state.
    # @public_api
    def stop
      # No cleanup to do for the SyncWriter
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
