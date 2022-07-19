require 'datadog/tracing/stats/repository'

module Datadog
  module Tracing
    module Stats
      # TOP-LEVEL class description
      class NullWriter
        def perform(_); end
      end

      # TOP-LEVEL class description
      class Writer < Core::Worker
        # Asynchronously
        include Core::Workers::Queue
        include Core::Workers::Polling

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
        #
        # WARNING: This method breaks the Liskov Substitution Principle -- TraceWriter#perform is spec'd to return the
        # result from the writer, whereas this method always returns nil.
        def perform(traces)
          enqueue(trace)
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

        # Are there more traces to be processed next?
        def work_pending?
          !buffer.empty?
        end

        def async?
          @async == true
        end

        def fork_policy=(policy)
          # Translate to Workers::Async::Thread policy
          thread_fork_policy =  case policy
                                when Core::Workers::Async::Thread::FORK_POLICY_STOP
                                  policy
                                when FORK_POLICY_SYNC
                                  # Stop the async thread because the writer
                                  # will bypass and run synchronously.
                                  Core::Workers::Async::Thread::FORK_POLICY_STOP
                                else
                                  Core::Workers::Async::Thread::FORK_POLICY_RESTART
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
      end
    end
  end
end
