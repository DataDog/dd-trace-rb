require 'time'
require 'ddtrace/buffer'
require 'ddtrace/transport'
require 'ddtrace/encoding'
require 'ddtrace/workers'
require 'ddtrace/span'

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

      # one worker for both services and traces, each have their own queues
      @worker = nil
    end

    # spawns two different workers for spans and services;
    # they share the same transport which is thread-safe
    def start
      @next_send_services = Time.now
      @worker = Datadog::Workers::AsyncTransport.new(@span_interval,
                                                     @transport,
                                                     [:traces, :services],
                                                     @buff_size) do |items, transport|
        send(items, transport)
      end

      @worker.start()
    end

    # stops both workers for spans and services.
    def stop
      @worker.stop()
      @worker = nil
    end

    # flush spans to the trace-agent, handles both spans & services
    def send(items, transport)
      return if items.empty?
      if items[0].instance_of? Array
        send_spans(items, transport)
      elsif items[0].instance_of? Hash
        if Time.now >= @next_send_services
          send_services(items, transport)
          @next_send_services = Time.now + @service_interval
        else
          @worker.enqueue(:services, items)
        end
      end
    end

    # flush spans to the trace-agent, handles spans only
    def send_spans(traces, transport)
      # FIXME[matt]: if there's an error, requeue; the new Transport can
      # behave differently if it's a server or a client error. Don't requeue
      # if we have a client error?
      transport.send(:traces, traces)

      @traces_flushed += traces.length()
    end

    # flush services to the trace-agent, handles services only
    def send_services(services, transport)
      # extract the services dictionary and keep it in the task queue for the next call,
      # so that even if we have communication problems (i.e. the trace agent isn't started yet) we
      # can resend the payload every +services_interval+ seconds
      services = services[0]
      @worker.enqueue(:services, services)

      transport.send(:services, services)
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

      @worker.enqueue(:traces, trace)
      @worker.enqueue(:services, services)
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
