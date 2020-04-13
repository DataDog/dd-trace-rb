require 'ddtrace/ext/net'
require 'ddtrace/runtime/socket'
require 'ddtrace/runtime/metrics'

module Datadog
  # SyncWriter flushes both services and traces synchronously
  # DEV: To be replaced by Datadog::Workers::TraceWriter.
  #
  # Note: If you're wondering if this class is used at all, since there are no other references to it on the codebase,
  # the separate `datadog-lambda` uses it as of February 2021:
  # <https://github.com/DataDog/datadog-lambda-rb/blob/c15f0f0916c90123416dc44e7d6800ef4a7cfdbf/lib/datadog/lambda.rb#L38>
  class SyncWriter
    attr_reader \
      :priority_sampler,
      :transport

    def initialize(options = {})
      @transport = options.fetch(:transport) do
        transport_options = options.fetch(:transport_options, {})
        Transport::HTTP.default(transport_options)
      end

      @priority_sampler = options.fetch(:priority_sampler, nil)
    end

    def write(trace, services = nil)
      unless services.nil?
        Datadog::Patcher.do_once('SyncWriter#write') do
          Datadog.logger.warn(%(
            write: Writing services has been deprecated and no longer need to be provided.
            write(traces, services) can be updted to write(traces)
          ))
        end
      end

      flush_trace(trace)
    rescue => e
      Datadog.logger.debug(e)
    end

    # Added for interface completeness
    def stop
      # No cleanup to do for the SyncWriter
      true
    end

    def flush_completed
      @flush_completed ||= FlushCompleted.new
    end

    # Flush completed event for worker
    class FlushCompleted < Event
      def initialize
        super(:flush_completed)
      end

      # NOTE: Ignore Rubocop rule. This definition allows for
      #       description of and constraints on arguments.
      # rubocop:disable Lint/UselessMethodDefinition
      def publish(response)
        super(response)
      end
      # rubocop:enable Lint/UselessMethodDefinition
    end

    private

    def flush_trace(trace)
      processed_traces = Pipeline.process!([trace])
      return if processed_traces.empty?

      inject_hostname!(processed_traces.first) if Datadog.configuration.report_hostname
      transport.send_traces(processed_traces)
    end

    def inject_hostname!(trace)
      unless trace.first.nil?
        hostname = Datadog::Runtime::Socket.hostname
        trace.first.set_tag(Ext::NET::TAG_HOSTNAME, hostname) unless hostname.nil? || hostname.empty?
      end
    end
  end
end
