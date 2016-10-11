require 'thread'
require 'ddtrace/buffer'
require 'ddtrace/transport'
require 'ddtrace/encoding'

module Datadog
  # Traces and services writer that periodically sends data to the trace-agent
  class Writer
    HOSTNAME = 'localhost'.freeze
    PORT = '7777'.freeze
    SPANS_ENDPOINT = '/spans'.freeze
    SERVICES_ENDPOINT = '/services'.freeze

    def initialize(options = {})
      # writer and transport parameters
      buffer_size = options.fetch(:buffer_size, 100)
      spans_interval = options.fetch(:spans_interval, 1)
      services_interval = options.fetch(:services_interval, 120)

      # transport and buffers
      @transport = options.fetch(:transport, Datadog::HTTPTransport.new(HOSTNAME, PORT))
      @trace_buffer = TraceBuffer.new(buffer_size)
      @services = {}

      @mutex = Mutex.new
      @traces_flushed = 0

      # spawns two different workers for spans and services;
      # they share the same transport which is thread-safe
      spans_worker(spans_interval)
      services_worker(services_interval)
    end

    # spawns a thread that will periodically flush spans to the agent
    def spans_worker(interval)
      Thread.new() do
        loop do
          send_spans()
          sleep(interval)
        end
      end
    end

    # spawns a thread that will periodically flush services to the agent
    def services_worker(interval)
      Thread.new() do
        loop do
          send_services()
          sleep(interval)
        end
      end
    end

    # flush spans to the trace-agent
    def send_spans
      traces = @trace_buffer.pop()
      return if traces.empty?

      spans = Datadog::Encoding.encode_spans(traces.flatten)
      # FIXME[matt]: if there's an error, requeue; the new Transport can
      # behave differently if it's a server or a client error. Don't requeue
      # if we have a client error?
      @transport.send(SPANS_ENDPOINT, spans)

      @mutex.synchronize do
        # TODO[all]: is it really required? it's a number that will grow indefinitely
        @traces_flushed += traces.length()
      end
    end

    # flush services to the trace-agent
    def send_services
      return if @services.empty?

      services = Datadog::Encoding.encode_services(@services)
      @transport.send(SERVICES_ENDPOINT, services)
    end

    # enqueue the trace for submission to the API
    def write(trace, services)
      @trace_buffer.push(trace)
      # TODO[manu]: provide a generic buffer that can be used also for services
      @services = services
    end

    # stats returns a dictionary of stats about the writer.
    def stats
      {
        traces_flushed: @traces_flushed,
        traces_buffered: @trace_buffer.length()
      }
    end
  end
end
