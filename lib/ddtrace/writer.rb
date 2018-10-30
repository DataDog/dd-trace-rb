require 'ddtrace/transport'
require 'ddtrace/encoding'
require 'ddtrace/workers'
require 'ddtrace/metrics'

module Datadog
  # Traces and services writer that periodically sends data to the trace-agent
  class Writer
    include Datadog::Metrics

    attr_reader :transport, :worker, :priority_sampler

    HOSTNAME = '127.0.0.1'.freeze
    PORT = '8126'.freeze

    METRIC_TRACES_FLUSHED = 'datadog.tracer.traces_flushed'.freeze
    METRIC_SERVICES_FLUSHED = 'datadog.tracer.services_flushed'.freeze

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
        HTTPTransport.new(HOSTNAME, PORT, transport_options)
      end

      @services = {}

      # handles the thread creation after an eventual fork
      @mutex_after_fork = Mutex.new
      @pid = nil

      # one worker for both services and traces, each have their own queues
      @worker = nil
    end

    # spawns two different workers for spans and services;
    # they share the same transport which is thread-safe
    def start
      @pid = Process.pid
      @trace_handler = ->(items, transport) { send_spans(items, transport) }
      @service_handler = ->(items, transport) { send_services(items, transport) }
      @worker = Datadog::Workers::AsyncTransport.new(@transport,
                                                     @buff_size,
                                                     @trace_handler,
                                                     @service_handler,
                                                     @flush_interval)

      @worker.start
    end

    # stops both workers for spans and services.
    def stop
      @worker.stop
      @worker = nil
    end

    # flush spans to the trace-agent, handles spans only
    def send_spans(traces, transport)
      return true if traces.empty?

      code = transport.send(:traces, traces)
      status = !transport.server_error?(code)
      increment(METRIC_TRACES_FLUSHED, by: traces.length) if status

      status
    end

    # flush services to the trace-agent, handles services only
    def send_services(services, transport)
      return true if services.empty?

      code = transport.send(:services, services)
      status = !transport.server_error?(code)
      increment(METRIC_SERVICES_FLUSHED) if status

      status
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

      @worker.enqueue_trace(trace)
      @worker.enqueue_service(services)
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
