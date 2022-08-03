# typed: false

module Datadog
  module Profiling
    module Collectors
      # Used to trigger the periodic execution of Collectors::CpuAndWallTime, which implements all of the sampling logic
      # itself; this class only implements the "doing it periodically" part.
      # Almost all of this class is implemented as native code.
      #
      # Methods prefixed with _native_ are implemented in `collectors_cpu_and_wall_time_worker.c`
      class CpuAndWallTimeWorker
        def initialize(
          recorder:,
          max_frames:,
          cpu_and_wall_time_collector: CpuAndWallTime.new(recorder: recorder, max_frames: max_frames)
        )
          self.class._native_initialize(self, cpu_and_wall_time_collector)
          @worker_thread = nil
          @start_stop_mutex = Mutex.new
        end

        def start
          @start_stop_mutex.synchronize do
            return if @worker_thread

            Datadog.logger.debug { "Starting thread for: #{self}" }
            @worker_thread = Thread.new do
              begin
                Thread.current.name = self.class.name unless Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.3')

                self.class._native_sampling_loop(self)

                Datadog.logger.debug('CpuAndWallTimeWorker thread stopping cleanly')
              rescue Exception => e
                @error = e
                Datadog.logger.warn(
                  "Worker thread error. Cause: #{e.class.name} #{e.message} Location: #{Array(e.backtrace).first}"
                )
                raise
              end
            end
          end

          true
        end

        # TODO: Provided only for compatibility with the API for Collectors::OldStack used in the Profiler class.
        # Can be removed once we remove OldStack.
        def enabled=(_)
        end

        def stop(_)
          @start_stop_mutex.synchronize do
            Datadog.logger.debug('Requesting CpuAndWallTimeWorker thread shut down')

            return unless @worker_thread

            self.class._native_stop(self)
            @worker_thread.join
            @worker_thread = nil
          end
        end
      end
    end
  end
end
