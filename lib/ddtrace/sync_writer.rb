module Datadog
  # SyncWriter flushes both services and traces synchronously
  class SyncWriter
    attr_reader :transport

    def initialize(options = {})
      @transport = options.fetch(:transport) do
        HTTPTransport.new(Writer::HOSTNAME, Writer::PORT)
      end
    end

    def write(trace, services)
      perform_concurrently(
        proc { flush_services(services) },
        proc { flush_trace(trace) }
      )
    rescue => e
      Tracer.log.debug(e)
    end

    private

    def perform_concurrently(*tasks)
      tasks.map { |task| Thread.new(&task) }.each(&:join)
    end

    def flush_services(services)
      transport.send(:services, services)
    end

    def flush_trace(trace)
      processed_traces = Pipeline.process!([trace])
      transport.send(:traces, processed_traces)
    end
  end
end
