require 'ddtrace/logger'
require 'ddtrace/transport/http'

require 'ddtrace/event'
require 'ddtrace/worker'
require 'ddtrace/workers/polling'
require 'ddtrace/workers/queue'

module Datadog
  module Workers
    # Writes traces to transport synchronously
    class TraceWriter < Worker
      attr_reader \
        :transport

      def initialize(options = {})
        transport_options = options.fetch(:transport_options, {})

        if transport_options.is_a?(Proc)
          transport_options = { on_build: transport_options }
        end

        transport_options[:hostname] = options[:hostname] if options.key?(:hostname)
        transport_options[:port] = options[:port] if options.key?(:port)

        @transport = options.fetch(:transport) do
          Transport::HTTP.default(transport_options)
        end
      end

      def perform(traces)
        write_traces(traces)
      end

      def write(trace)
        write_traces([trace])
      end

      def write_traces(traces)
        traces = process_traces(traces)
        flush_traces(traces)
      rescue StandardError => e
        Datadog.logger.error(
          "Error while writing traces: dropped #{traces.length} items. Cause: #{e} Location: #{e.backtrace.first}"
        )
      end

      def process_traces(traces)
        # Run traces through the processing pipeline
        traces = Pipeline.process!(traces)

        # Inject hostname if configured to do so
        inject_hostname!(traces) if Datadog.configuration.report_hostname

        traces
      end

      def flush_traces(traces)
        transport.send_traces(traces).tap do |response|
          flush_completed.publish(response)
        end
      end

      def inject_hostname!(traces)
        traces.each do |trace|
          next if trace.first.nil?

          hostname = Datadog::Runtime::Socket.hostname
          unless hostname.nil? || hostname.empty?
            trace.first.set_tag(Ext::NET::TAG_HOSTNAME, hostname)
          end
        end
      end

      # TODO: Register `Datadog::Diagnostics::EnvironmentLogger.log!`
      # TODO: as a flush_completed subscriber when the `TraceWriter`
      # TODO: instantiation code is implemented.
      def flush_completed
        @flush_completed ||= FlushCompleted.new
      end

      # Flush completed event for worker
      class FlushCompleted < Event
        def initialize
          super(:flush_completed)
        end

        def publish(response)
          super(response)
        end
      end
    end

    # Writes traces to transport asynchronously,
    # using a thread & buffer.
    class AsyncTraceWriter < TraceWriter
      include Workers::Queue
      include Workers::Polling

      DEFAULT_BUFFER_MAX_SIZE = 1000
      FORK_POLICY_ASYNC = :async
      FORK_POLICY_SYNC = :sync

      attr_writer \
        :async

      def initialize(options = {})
        # Workers::TraceWriter settings
        super

        # Workers::Polling settings
        self.enabled = options.fetch(:enabled, true)

        # Workers::Async::Thread settings
        @async = true
        self.fork_policy = options.fetch(:fork_policy, FORK_POLICY_ASYNC)

        # Workers::IntervalLoop settings
        self.loop_base_interval = options[:interval] if options.key?(:interval)
        self.loop_back_off_ratio = options[:back_off_ratio] if options.key?(:back_off_ratio)
        self.loop_back_off_max = options[:back_off_max] if options.key?(:back_off_max)

        # Workers::Queue settings
        @buffer_size = options.fetch(:buffer_size, DEFAULT_BUFFER_MAX_SIZE)
        self.buffer = TraceBuffer.new(@buffer_size)
      end

      # NOTE: #perform is wrapped by other modules:
      #       Polling --> Async --> IntervalLoop --> AsyncTraceWriter --> TraceWriter
      def perform(traces)
        super(traces).tap do |responses|
          loop_back_off! if responses.find(&:server_error?)
        end
      end

      def stop(*args)
        buffer.close if running?
        super
      end

      def enqueue(trace)
        buffer.push(trace)
      end

      def dequeue
        # Wrap results in Array because they are
        # splatted as args against TraceWriter#perform.
        [buffer.pop]
      end

      def work_pending?
        !buffer.empty?
      end

      def async?
        @async == true
      end

      def fork_policy=(policy)
        # Translate to Workers::Async::Thread policy
        thread_fork_policy = case policy
                             when Workers::Async::Thread::FORK_POLICY_STOP
                               policy
                             when FORK_POLICY_SYNC
                               # Stop the async thread because the writer
                               # will bypass and run synchronously.
                               Workers::Async::Thread::FORK_POLICY_STOP
                             else
                               Workers::Async::Thread::FORK_POLICY_RESTART
                             end

        # Update thread fork policy
        super(thread_fork_policy)

        # Update local policy
        @writer_fork_policy = policy
      end

      def after_fork
        # In multiprocess environments, forks will share the same buffer until its written to.
        # A.K.A. copy-on-write. We don't want forks to write traces generated from another process.
        # Instead, we reset it after the fork. (Make sure any enqueue operations happen after this.)
        self.buffer = TraceBuffer.new(@buffer_size)

        # Switch to synchronous mode if configured to do so.
        # In some cases synchronous writing is preferred because the fork will be short lived.
        @async = false if @writer_fork_policy == FORK_POLICY_SYNC
      end

      def write(trace)
        # Start worker thread. If the process has forked, it will trigger #after_fork to
        # reconfigure the worker accordingly.
        # NOTE: It's important we do this before queuing or it will drop the current trace,
        #       because #after_fork resets the buffer.
        perform

        # Queue the trace if running asynchronously, otherwise short-circuit and write it directly.
        async? ? enqueue(trace) : write_traces([trace])
      end
    end
  end
end
