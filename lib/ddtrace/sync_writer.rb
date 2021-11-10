# typed: true
require 'ddtrace/pipeline'
require 'ddtrace/ext/net'
require 'datadog/core/environment/socket'
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

    def initialize(options = {})
      @transport = options.fetch(:transport) do
        transport_options = options.fetch(:transport_options, {})
        transport_options[:agent_settings] = options[:agent_settings] if options.key?(:agent_settings)
        Transport::HTTP.default(**transport_options)
      end

      @events = Writer::Events.new
    end

    def write(trace)
      flush_trace(trace)
    rescue => e
      Datadog.logger.debug(e)
    end

    # Added for interface completeness
    def stop
      # No cleanup to do for the SyncWriter
      true
    end

    private

    def flush_trace(trace)
      processed_traces = Pipeline.process!([trace])
      return if processed_traces.empty?

      inject_hostname!(processed_traces.first) if Datadog.configuration.report_hostname
      responses = transport.send_traces(processed_traces)

      events.after_send.publish(self, responses)

      responses
    end

    def inject_hostname!(trace)
      unless trace.first.nil?
        hostname = Datadog::Core::Environment::Socket.hostname
        trace.first.set_tag(Ext::NET::TAG_HOSTNAME, hostname) unless hostname.nil? || hostname.empty?
      end
    end
  end
end
