module Datadog
  module Profiling
    module Collectors
      # Used by the Collectors::CpuAndWallTimeWorker to gather samples when the Ruby process is idle.
      # Almost all of this class is implemented as native code.
      #
      # Methods prefixed with _native_ are implemented in `collectors_idle_sampling_helper.c`
      class IdleSamplingHelper
        private

        attr_accessor :failure_exception

        public

        def initialize
          @worker_thread = nil
          @start_stop_mutex = Mutex.new
        end

        def start
          @start_stop_mutex.synchronize do
            return if @worker_thread && @worker_thread.alive?

            Datadog.logger.debug { "Starting thread for: #{self}" }

            # The same instance of the IdleSamplingHelper can be reused multiple times, and this resets it back to
            # a pristine state before recreating the worker thread
            self.class._native_reset(self)

            @worker_thread = Thread.new do
              begin
                Thread.current.name = self.class.name

                self.class._native_idle_sampling_loop(self)

                Datadog.logger.debug('IdleSamplingHelper thread stopping cleanly')
              rescue Exception => e # rubocop:disable Lint/RescueException
                @failure_exception = e
                Datadog.logger.warn(
                  'IdleSamplingHelper thread error. ' \
                  "Cause: #{e.class.name} #{e.message} Location: #{Array(e.backtrace).first}"
                )
              end
            end
          end

          true
        end

        def stop(*_unused)
          @start_stop_mutex.synchronize do
            Datadog.logger.debug('Requesting IdleSamplingHelper thread shut down')

            return unless @worker_thread

            self.class._native_stop(self)

            @worker_thread.join
            @worker_thread = nil
            @failure_exception = nil
          end
        end
      end
    end
  end
end
