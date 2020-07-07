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

      # handles the thread creation after an eventual fork
      @mutex_after_fork = Mutex.new
      @pid = nil

      @traces_flushed = 0

      # one worker for traces
      @worker = nil
    end

    def start
      @mutex_after_fork.synchronize do
        pid = Process.pid
        return if @worker && pid == @pid
        @pid = pid
        start_worker
        true
      end
    end

    # spawns a worker for spans; they share the same transport which is thread-safe
    def start_worker
      @trace_handler = ->(items, transport) { send_spans(items, transport) }
      @worker = Datadog::Workers::AsyncTransport.new(
        transport: @transport,
        buffer_size: @buff_size,
        on_trace: @trace_handler,
        interval: @flush_interval
      )

      @worker.start
    end

    def stop
      @mutex_after_fork.synchronize { stop_worker }
    end

    def stop_worker
      return if @worker.nil?
      @worker.stop
      @worker = nil
      true
    end

    private :start_worker, :stop_worker

    # flush spans to the trace-agent, handles spans only
    def send_spans(traces, transport)
      return true if traces.empty?

      # Inject hostname if configured to do so
      inject_hostname!(traces) if Datadog.configuration.report_hostname

      # Send traces and get responses
      responses = transport.send_traces(traces)

      # Tally up successful flushes
      responses.reject { |x| x.internal_error? || x.server_error? }.each do |response|
        @traces_flushed += response.trace_count
      end

      # Update priority sampler
      update_priority_sampler(responses.last)

      # Return if server error occurred.
      !responses.find(&:server_error?)
    end

    # enqueue the trace for submission to the API
    def write(trace, services = nil)
      unless services.nil?
        Datadog::Patcher.do_once('Writer#write') do
          Datadog.logger.warn(%(
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
      start if @worker.nil? || @pid != Process.pid

      # TODO: Remove this, and have the tracer pump traces directly to runtime metrics
      #       instead of working through the trace writer.
      # Associate root span with runtime metrics
      if Datadog.configuration.runtime_metrics.enabled && !trace.empty?
        Datadog.runtime_metrics.associate_with_span(trace.first)
      end

      worker_local = @worker

      if worker_local
        worker_local.enqueue_trace(trace)
      else
        Datadog.logger.debug('Writer either failed to start or was stopped before #write could complete')
      end
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

    def update_priority_sampler(response)
      return unless response && !response.internal_error? && priority_sampler && response.service_rates

      priority_sampler.update(response.service_rates)
    end
  end
end
