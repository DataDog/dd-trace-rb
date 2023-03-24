module Datadog
  module Profiling
    module Collectors
      # Used to trigger the periodic execution of Collectors::ThreadState, which implements all of the sampling logic
      # itself; this class only implements the "when to do it" part.
      # Almost all of this class is implemented as native code.
      #
      # Methods prefixed with _native_ are implemented in `collectors_cpu_and_wall_time_worker.c`
      class CpuAndWallTimeWorker
        private

        attr_accessor :failure_exception

        public

        def initialize(
          recorder:,
          max_frames:,
          tracer:,
          endpoint_collection_enabled:,
          gc_profiling_enabled:,
          allocation_counting_enabled:,
          thread_context_collector: ThreadContext.new(
            recorder: recorder,
            max_frames: max_frames,
            tracer: tracer,
            endpoint_collection_enabled: endpoint_collection_enabled,
          ),
          idle_sampling_helper: IdleSamplingHelper.new,
          # **NOTE**: This should only be used for testing; disabling the dynamic sampling rate will increase the
          # profiler overhead!
          dynamic_sampling_rate_enabled: true
        )
          unless dynamic_sampling_rate_enabled
            Datadog.logger.warn(
              'Profiling dynamic sampling rate disabled. This should only be used for testing, and will increase overhead!'
            )
          end

          self.class._native_initialize(
            self,
            thread_context_collector,
            gc_profiling_enabled,
            idle_sampling_helper,
            allocation_counting_enabled,
            dynamic_sampling_rate_enabled,
          )
          @worker_thread = nil
          @failure_exception = nil
          @start_stop_mutex = Mutex.new
          @idle_sampling_helper = idle_sampling_helper
        end

        def start
          @start_stop_mutex.synchronize do
            return if @worker_thread && @worker_thread.alive?

            Datadog.logger.debug { "Starting thread for: #{self}" }

            @idle_sampling_helper.start

            @worker_thread = Thread.new do
              begin
                Thread.current.name = self.class.name

                self.class._native_sampling_loop(self)

                Datadog.logger.debug('CpuAndWallTimeWorker thread stopping cleanly')
              rescue Exception => e # rubocop:disable Lint/RescueException
                @failure_exception = e
                Datadog.logger.warn(
                  'CpuAndWallTimeWorker thread error. ' \
                  "Cause: #{e.class.name} #{e.message} Location: #{Array(e.backtrace).first}"
                )
              end
            end
          end

          true
        end

        # TODO: Provided only for compatibility with the API for Collectors::OldStack used in the Profiler class.
        # Can be removed once we remove OldStack.
        def enabled=(_); end

        def stop(*_)
          @start_stop_mutex.synchronize do
            Datadog.logger.debug('Requesting CpuAndWallTimeWorker thread shut down')

            @idle_sampling_helper.stop

            return unless @worker_thread

            self.class._native_stop(self, @worker_thread)

            @worker_thread.join
            @worker_thread = nil
            @failure_exception = nil
          end
        end

        def reset_after_fork
          self.class._native_reset_after_fork(self)
        end

        def stats
          self.class._native_stats(self)
        end
      end
    end
  end
end
