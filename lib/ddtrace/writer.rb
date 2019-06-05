require 'json'

require 'ddtrace/ext/net'
require 'ddtrace/runtime/socket'

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
        transport_options[:response_callback] ||= method(:old_sampling_updater)
      end

      # transport and buffers
      @transport = options.fetch(:transport) do
        HTTPTransport.new(transport_options)
      end

      # Runtime metrics
      @runtime_metrics = options.fetch(:runtime_metrics) do
        Runtime::Metrics.new
      end

      # handles the thread creation after an eventual fork
      @mutex_after_fork = Mutex.new
      @pid = nil

      @traces_flushed = 0

      # one worker for traces
      @worker = nil
    end

    # spawns a worker for spans; they share the same transport which is thread-safe
    def start
      @pid = Process.pid
      @trace_handler = ->(items, transport) { send_spans(items, transport) }
      @runtime_metrics_handler = -> { send_runtime_metrics }
      @worker = Datadog::Workers::AsyncTransport.new(
        transport: @transport,
        buffer_size: @buff_size,
        on_trace: @trace_handler,
        on_runtime_metrics: @runtime_metrics_handler,
        interval: @flush_interval
      )

      @worker.start()
    end

    # stops worker for spans.
    def stop
      @worker.stop()
      @worker = nil
    end

    # flush spans to the trace-agent, handles spans only
    def send_spans(traces, transport)
      return true if traces.empty?

      # Inject hostname if configured to do so
      inject_hostname!(traces) if Datadog.configuration.report_hostname

      if transport.is_a?(Datadog::HTTPTransport)
        # For older Datadog::HTTPTransport...
        code = transport.send(:traces, traces)
        !transport.server_error?(code).tap do |status|
          @traces_flushed += traces.length if status
        end
      else
        # For newer Datadog::Transports...
        request = Transport::Request.new(:traces, Transport::Traces::Parcel.new(traces))
        response = transport.deliver(request)
        !response.server_error? do |status|
          @traces_flushed += traces.length if status
          update_priority_sampler!(response)
        end
      end
    end

    def send_runtime_metrics
      return unless Datadog.configuration.runtime_metrics_enabled

      runtime_metrics.flush
    end

    # enqueue the trace for submission to the API
    def write(trace, services = nil)
      unless services.nil?
        Datadog::Patcher.do_once('Writer#write') do
          Datadog::Tracer.log.warn(%(
            write: Writing services has been deprecated and no longer need to be provided.
            write(traces, services) can be updted to write(traces)
          ))
        end
      end

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
    end

    # stats returns a dictionary of stats about the writer.
    def stats
      {
        traces_flushed: @traces_flushed,
        transport: @transport.stats
      }
    end

    private

    def inject_hostname!(traces)
      traces.each do |trace|
        next if trace.first.nil?

        hostname = Datadog::Runtime::Socket.hostname
        unless hostname.nil? || hostname.empty?
          trace.first.set_tag(Ext::NET::TAG_HOSTNAME, hostname)
        end
      end
    end

    # Updates the priority sampler with rates from transport response.
    # response: A Datadog::Transport::Response object.
    def update_priority_sampler!(response)
      return if priority_sampler.nil? || response.payload.nil?
      # TODO: Check if response is priority sampling compatible

      body = JSON.parse(response.payload)
      if body.is_a?(Hash) && body.key?('rate_by_service')
        priority_sampler.update(body['rate_by_service'])
      end
    end

    # Updates the priority sampler with rates from transport response.
    # action (Symbol): Symbol representing data submitted.
    # response: A Datadog::Transport::Response object.
    # api: API version used to process this request.
    #
    # NOTE: Used only by old Datadog::HTTPTransport; will be removed.
    def old_sampling_updater(action, response, api)
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
