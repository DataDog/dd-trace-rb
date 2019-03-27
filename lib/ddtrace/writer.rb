require 'ddtrace/transport'
require 'ddtrace/encoding'
require 'ddtrace/workers'

module Datadog
  # Processor that sends traces and metadata to the agent
  class Writer
    attr_reader \
      :priority_sampler,
      :runtime_metrics,
      :transport,
      :worker

    def initialize(options = {})
      # writer and transport parameters
      @buff_size = options.fetch(:buffer_size, 100)
      @flush_interval = options.fetch(:flush_interval, 1)
      transport_options = options.fetch(:transport_options, {})

      # priority sampling
      if options[:priority_sampler]
        @priority_sampler = options[:priority_sampler]
        transport_options[:api_version] ||= HTTPTransport::V4
        transport_options[:response_callback] ||= method(:sampling_updater)
      end

      # transport and buffers
      @transport = options.fetch(:transport) do
        HTTPTransport.new(transport_options)
      end

      # Runtime metrics
      @runtime_metrics = options.fetch(:runtime_metrics) do
        Runtime::Metrics.new
      end

      @services = {}

      # handles the thread creation after an eventual fork
      @mutex_after_fork = Mutex.new
      @pid = nil

      @traces_flushed = 0
      @services_flushed = 0

      # one worker for both services and traces, each have their own queues
      @worker = nil
    end

    # spawns two different workers for spans and services;
    # they share the same transport which is thread-safe
    def start
      @pid = Process.pid
      @trace_handler = ->(items, transport) { send_spans(items, transport) }
      @service_handler = ->(items, transport) { send_services(items, transport) }
      @runtime_metrics_handler = -> { send_runtime_metrics }
      @worker = Datadog::Workers::AsyncTransport.new(
        transport: @transport,
        buffer_size: @buff_size,
        on_trace: @trace_handler,
        on_service: @service_handler,
        on_runtime_metrics: @runtime_metrics_handler,
        interval: @flush_interval
      )

      @worker.start()
    end

    # stops both workers for spans and services.
    def stop
      @worker.stop()
      @worker = nil
    end

    # flush spans to the trace-agent, handles spans only
    def send_spans(traces, transport)
      return true if traces.empty?

      code = transport.send(:traces, traces)
      status = !transport.server_error?(code)
      @traces_flushed += traces.length if status

      status
    end

    # flush services to the trace-agent, handles services only
    def send_services(services, transport)
      return true if services.empty?

      code = transport.send(:services, services)
      status = !transport.server_error?(code)
      @services_flushed += 1 if status

      status
    end

    def send_runtime_metrics
      runtime_metrics.flush
    end

    # enqueue the trace for submission to the API
    def write(trace, services)
      # In multiprocess environments, the main process initializes the +Writer+ instance and if
      # the process forks (i.e. a web server like Unicorn or Puma with multiple workers) the new
      # processes will share the same +Writer+ until the first write (COW). Because of that,
      # each process owns a different copy of the +@buffer+ after each write and so the
      # +AsyncTransport+ will not send data to the trace agent.
      #
      # This check ensures that if a process doesn't own the current +Writer+, async workers
      # will be initialized again (but only once for each process).
      pid = Process.pid
      if pid != @pid # avoid using Mutex when pids are equal
        @mutex_after_fork.synchronize do
          # we should start threads because the worker doesn't own this
          start if pid != @pid
        end
      end

      # Associate root span with runtime metrics
      runtime_metrics.associate_with_span(trace.first) unless trace.empty?

      @worker.enqueue_trace(trace)
      @worker.enqueue_service(services)
    end

    # stats returns a dictionary of stats about the writer.
    def stats
      {
        traces_flushed: @traces_flushed,
        services_flushed: @services_flushed,
        transport: @transport.stats
      }
    end

    private

    def sampling_updater(action, response, api)
      return unless action == :traces && response.is_a?(Net::HTTPOK)

      if api[:version] == HTTPTransport::V4
        body = JSON.parse(response.body)
        if body.is_a?(Hash) && body.key?('rate_by_service')
          @priority_sampler.update(body['rate_by_service'])
        end
        true
      else
        false
      end
    end
  end
end
