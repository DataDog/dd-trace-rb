require 'json'

require 'ddtrace/ext/net'
require 'ddtrace/runtime/socket'

require 'ddtrace/transport/http'
require 'ddtrace/transport/io'
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
      @buff_size = options.fetch(:buffer_size, Workers::AsyncTransport::DEFAULT_BUFFER_MAX_SIZE)
      @flush_interval = options.fetch(:flush_interval, Workers::AsyncTransport::DEFAULT_FLUSH_INTERVAL)
      transport_options = options.fetch(:transport_options, {})

      # priority sampling
      if options[:priority_sampler]
        @priority_sampler = options[:priority_sampler]
        transport_options[:api_version] ||= Transport::HTTP::API::V4
      end

      # transport and buffers
      @transport = options.fetch(:transport) do
        Transport::HTTP.default(transport_options)
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

      @worker.start
    end

    # stops worker for spans.
    def stop
      return if worker.nil?
      @worker.stop.tap { @worker = nil }
    end

    # flush spans to the trace-agent, handles spans only
    def send_spans(traces, transport)
      return true if traces.empty?

      # Inject hostname if configured to do so
      inject_hostname!(traces) if Datadog.configuration.report_hostname

      # Send traces an get a response.
      response = transport.send_traces(traces)

      unless response.internal_error?
        @traces_flushed += traces.length unless response.server_error?

        # Update priority sampler
        unless priority_sampler.nil? || response.service_rates.nil?
          priority_sampler.update(response.service_rates)
        end
      end

      # Return if server error occurred.
      !response.server_error?
    end

    def send_runtime_metrics
      return unless Datadog.configuration.runtime_metrics_enabled

      runtime_metrics.flush
    end

    # enqueue the trace for submission to the API
    def write(trace, services = nil)
      unless services.nil?
        Datadog::Patcher.do_once('Writer#write') do
          Datadog::Logger.log.warn(%(
            write: Writing services has been deprecated and no longer need to be provided.
            write(traces, services) can be updated to write(traces)
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
      if Datadog.configuration.runtime_metrics_enabled && !trace.empty?
        runtime_metrics.associate_with_span(trace.first)
      end

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
  end
end
