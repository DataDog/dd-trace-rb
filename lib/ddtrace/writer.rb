require 'ddtrace/transport'
require 'ddtrace/encoding'
require 'ddtrace/workers'
require 'ddtrace/metrics'

module Datadog
  # Traces and services writer that periodically sends data to the trace-agent
  class Writer
    include Datadog::Metrics

    attr_reader :transport, :worker, :priority_sampler

    METRIC_SAMPLING_UPDATE_TIME = 'datadog.tracer.sampling_update_time'.freeze
    METRIC_SERVICES_FLUSHED = 'datadog.tracer.services_flushed'.freeze
    METRIC_FLUSH_TIME = 'datadog.tracer.writer.flush_time'.freeze
    METRIC_TRACES_FLUSHED = 'datadog.tracer.traces_flushed'.freeze
    TAG_DATA_TYPE = 'datadog.tracer.writer.data_type'.freeze
    TAG_DATA_TYPE_SERVICES = "#{TAG_DATA_TYPE}:services".freeze
    TAG_DATA_TYPE_TRACES = "#{TAG_DATA_TYPE}:traces".freeze
    TAG_PRIORITY_SAMPLING = 'datadog.tracer.writer.priority_sampling'.freeze
    TAG_PRIORITY_SAMPLING_DISABLED = 'datadog.tracer.writer.priority_sampling:false'.freeze
    TAG_PRIORITY_SAMPLING_ENABLED = 'datadog.tracer.writer.priority_sampling:true'.freeze

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
      time(METRIC_FLUSH_TIME, tags: [TAG_DATA_TYPE_TRACES]) do
        return true if traces.empty?

        code = transport.send(:traces, traces)
        status = !transport.server_error?(code)
        increment(METRIC_TRACES_FLUSHED, by: traces.length) if status

        status
      end
    end

    # flush services to the trace-agent, handles services only
    def send_services(services, transport)
      time(METRIC_FLUSH_TIME, tags: [TAG_DATA_TYPE_SERVICES]) do
        return true if services.empty?

        code = transport.send(:services, services)
        status = !transport.server_error?(code)
        increment(METRIC_SERVICES_FLUSHED) if status

        status
      end
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

      priority_sampling_tag = !@priority_sampler.nil? ? TAG_PRIORITY_SAMPLING_ENABLED : TAG_PRIORITY_SAMPLING_DISABLED
      time(METRIC_SAMPLING_UPDATE_TIME, tags: [priority_sampling_tag]) do
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
end
