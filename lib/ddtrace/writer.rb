require 'ddtrace/buffer'
require 'ddtrace/transport'
require 'ddtrace/encoding'
require 'ddtrace/workers'

module Datadog
  # Traces and services writer that periodically sends data to the trace-agent
  class Writer
    attr_reader :transport

    HOSTNAME = 'localhost'.freeze
    PORT = '7777'.freeze

    def initialize(options = {})
      # writer and transport parameters
      @buff_size = options.fetch(:buffer_size, 100)
      @span_interval = options.fetch(:spans_interval, 1)
      @service_interval = options.fetch(:services_interval, 120)

      # transport and buffers
      @transport = options.fetch(:transport, Datadog::HTTPTransport.new(HOSTNAME, PORT))
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
      @trace_handler = ->(items, transport) { send_spans(items, transport) }
      @service_handler = ->(items, transport) { send_services(items, transport) }
      @worker = Datadog::Workers::AsyncTransport.new(@span_interval,
                                                     @service_interval,
                                                     @transport,
                                                     @buff_size,
                                                     @trace_handler,
                                                     @service_handler)

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

      spans = Datadog::Encoding.encode_spans(traces)
      code = transport.send(SPANS_ENDPOINT, spans)

      if transport.server_error? code # requeue on server error, skip on success or client error
        traces[0..@buff_size].each do |trace|
          @worker.enqueue_trace trace
        end
        return false
      end

      @traces_flushed += traces.length()
      true
    end

    # flush services to the trace-agent, handles services only
    def send_services(services, transport)
      return true if services.empty?

      encoded_services = Datadog::Encoding.encode_services(services)
      code = transport.send(SERVICES_ENDPOINT, encoded_services)
      if transport.server_error? code # requeue on server error, skip on success or client error
        @worker.enqueue_service services
        return false
      end

      @services_flushed += 1
      true
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
      @mutex_after_fork.synchronize do
        if pid != @pid
          @pid = pid
          # we should start threads because the worker doesn't own this
          start()
        end
      end

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
  end
end
