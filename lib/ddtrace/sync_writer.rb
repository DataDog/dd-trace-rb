require 'ddtrace/runtime/metrics'

module Datadog
  # SyncWriter flushes both services and traces synchronously
  class SyncWriter
    attr_reader \
      :runtime_metrics,
      :transport

    def initialize(options = {})
      @transport = options.fetch(:transport) do
        transport_options = options.fetch(:transport_options, {})
        HTTPTransport.new(transport_options)
      end

      # Runtime metrics
      @runtime_metrics = options.fetch(:runtime_metrics) do
        Runtime::Metrics.new
      end
    end

    def write(trace, services = nil)
      unless services.nil?
        Datadog::Patcher.do_once('SyncWriter#write') do
          Datadog::Tracer.log.warn(%(
            write: Writing services has been deprecated and no longer need to be provided.
            write(traces, services) can be updted to write(traces)
          ))
        end
      end

      perform_concurrently(
        proc { flush_trace(trace) }
      )
    rescue => e
      Tracer.log.debug(e)
    end

    private

    def perform_concurrently(*tasks)
      tasks.map { |task| Thread.new(&task) }.each(&:join)
    end

    def flush_trace(trace)
      processed_traces = Pipeline.process!([trace])
      transport.send(:traces, processed_traces)
    end
  end
end
