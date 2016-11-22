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
    SPANS_ENDPOINT = '/v0.2/traces'.freeze
    SERVICES_ENDPOINT = '/v0.2/services'.freeze

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

      # spawns two different workers for spans and services;
      # they share the same transport which is thread-safe
      @trace_worker = nil
      @service_worker = nil
    end

    # spawns two different workers for spans and services;
    # they share the same transport which is thread-safe
    def start
      @trace_worker = Datadog::Workers::AsyncTransport.new(@span_interval, @transport, @buff_size) do |items, transport|
        send_spans(items, transport)
      end
      @service_worker = Datadog::Workers::AsyncTransport.new(@service_interval, @transport, 1) do |items, transport|
        send_services(items, transport)
      end

      @trace_worker.start()
      @service_worker.start()
    end

    # stops both workers for spans and services.
    def stop
      @trace_worker.stop()
      @trace_worker = nil
      @service_worker.stop()
      @service_worker = nil
    end

    # flush spans to the trace-agent
    def send_spans(traces, transport)
      # FIXME[matt]: if there's an error, requeue; the new Transport can
      # behave differently if it's a server or a client error. Don't requeue
      # if we have a client error?
      spans = Datadog::Encoding.encode_spans(traces)
      transport.send(SPANS_ENDPOINT, spans)

      # TODO[all]: is it really required? it's a number that will grow indefinitely
      @traces_flushed += traces.length()
    end

    # flush services to the trace-agent
    def send_services(services, transport)
      # extract the services dictionary and keep it in the task queue for the next call,
      # so that even if we have communication problems (i.e. the trace agent isn't started yet) we
      # can resend the payload every +services_interval+ seconds
      services = services[0]
      @service_worker.enqueue(services)

      services = Datadog::Encoding.encode_services(services)
      transport.send(SERVICES_ENDPOINT, services)
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

      @trace_worker.enqueue(trace)
      @service_worker.enqueue(services)
    end

    # stats returns a dictionary of stats about the writer.
    def stats
      {
        traces_flushed: @traces_flushed,
        transport: @transport.stats
      }
    end
  end
end
