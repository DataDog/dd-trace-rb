# frozen_string_literal: true

require_relative "../../core/utils/at_fork_monkey_patch"

module Datadog
  module Profiling
    module Collectors
      # Used to trigger the periodic execution of Collectors::ThreadState, which implements all of the sampling logic
      # itself; this class only implements the "when to do it" part.
      # Almost all of this class is implemented as native code.
      #
      # Methods prefixed with _native_ are implemented in `collectors_cpu_and_wall_time_worker.c`
      class CpuAndWallTimeWorker
        # @rbs @worker_thread: untyped
        # @rbs @start_stop_mutex: ::Thread::Mutex
        # @rbs @idle_sampling_helper: IdleSamplingHelper
        # @rbs @worker_state: WorkerState
        # @rbs @miteruby_serializer: Miteruby::Serializer?
        # @rbs @miteruby_consumer_thread: Thread?
        # @rbs @miteruby_consumer_enabled: bool
        # @rbs @miteruby_fork_hooks: Hash[Symbol, Proc]?
        # @rbs @miteruby_fork_depth: Integer
        # @rbs @miteruby_pid: Integer

        # @rbs gc_profiling_enabled: bool
        # @rbs no_signals_workaround_enabled: bool
        # @rbs thread_context_collector: ThreadContext?
        # @rbs dynamic_sampling_rate_overhead_target_percentage: Float
        # @rbs cpu_sampling_interval_ms: ::Integer
        # @rbs idle_sampling_helper: Datadog::Profiling::Collectors::IdleSamplingHelper
        # @rbs dynamic_sampling_rate_enabled: bool
        # @rbs allocation_profiling_enabled: bool
        # @rbs allocation_counting_enabled: bool
        # @rbs gvl_profiling_enabled: bool
        # @rbs sighandler_sampling_enabled: bool
        # @rbs miteruby_enabled: bool
        # @rbs waiting_for_gvl_threshold_ns: ::Integer
        # @rbs skip_idle_samples_for_testing: false
        # @rbs return: void
        def initialize(
          gc_profiling_enabled:,
          no_signals_workaround_enabled:,
          thread_context_collector:,
          dynamic_sampling_rate_overhead_target_percentage:,
          allocation_profiling_enabled:,
          allocation_counting_enabled:,
          gvl_profiling_enabled:,
          sighandler_sampling_enabled:,
          cpu_sampling_interval_ms:,
          waiting_for_gvl_threshold_ns:,
          miteruby_enabled: false,
          # **NOTE**: This should only be used for testing; disabling the dynamic sampling rate will increase the
          # profiler overhead!
          dynamic_sampling_rate_enabled: true,
          skip_idle_samples_for_testing: false,
          idle_sampling_helper: IdleSamplingHelper.new
        )
          if miteruby_enabled
            Datadog.logger.warn("MITERUBY enabled!!!")
          end
          unless dynamic_sampling_rate_enabled
            Datadog.logger.warn(
              "Profiling dynamic sampling rate disabled. This should only be used for testing, and will increase overhead!",
            )
            Datadog::Core::Telemetry::Logger.error(
              "Profiling dynamic sampling rate disabled. This should only be used for testing, and will increase overhead!",
            )
          end

          if cpu_sampling_interval_ms < 1
            raise ArgumentError, "cpu_sampling_interval_ms must be a positive integer, got #{cpu_sampling_interval_ms}"
          end

          self.class._native_initialize(
            self_instance: self,
            thread_context_collector: thread_context_collector,
            gc_profiling_enabled: gc_profiling_enabled,
            idle_sampling_helper: idle_sampling_helper,
            no_signals_workaround_enabled: no_signals_workaround_enabled,
            dynamic_sampling_rate_enabled: dynamic_sampling_rate_enabled,
            dynamic_sampling_rate_overhead_target_percentage: dynamic_sampling_rate_overhead_target_percentage,
            allocation_profiling_enabled: allocation_profiling_enabled,
            allocation_counting_enabled: allocation_counting_enabled,
            gvl_profiling_enabled: gvl_profiling_enabled,
            sighandler_sampling_enabled: sighandler_sampling_enabled,
            miteruby_enabled: miteruby_enabled,
            skip_idle_samples_for_testing: skip_idle_samples_for_testing,
            cpu_sampling_interval_ms: cpu_sampling_interval_ms,
            waiting_for_gvl_threshold_ns: waiting_for_gvl_threshold_ns,
          )
          @worker_thread = nil
          @start_stop_mutex = Mutex.new
          @idle_sampling_helper = idle_sampling_helper
          @worker_state = WorkerState.new
          @miteruby_serializer = miteruby_enabled ? Miteruby::Serializer.new : nil
          @miteruby_consumer_thread = nil
          @miteruby_consumer_enabled = false
          @miteruby_fork_hooks = nil
          @miteruby_fork_depth = 0
          @miteruby_pid = Process.pid
        end

        # @rbs on_failure_proc: (^(?log_failure: bool) -> void)?
        # @rbs return: bool?
        def start(on_failure_proc: nil)
          @start_stop_mutex.synchronize do
            return if @worker_thread&.alive?

            Datadog.logger.debug { "Starting thread for: #{self}" }

            reset_miteruby_after_fork
            register_miteruby_fork_hooks
            @miteruby_consumer_enabled = true if @miteruby_serializer
            @idle_sampling_helper.start(self)
            @miteruby_consumer_thread = create_miteruby_consumer

            @worker_thread = Thread.new do
              Thread.current.name = self.class.name

              self.class._native_sampling_loop(self)

              Datadog.logger.debug("CpuAndWallTimeWorker thread stopping cleanly")
            rescue Profiling::ExistingSignalHandler => e
              @worker_state.failed!(e)
              Datadog.logger.warn(
                "Profiling was not started as another profiler or gem is already using the SIGPROF signal. " \
                "Please disable the other profiler to use Datadog profiling.",
              )
              on_failure_proc&.call(log_failure: false)
            rescue Exception => e # rubocop:disable Lint/RescueException
              @worker_state.failed!(e)
              operation_name = self.class._native_failure_exception_during_operation(self).inspect
              Datadog.logger.warn(
                "CpuAndWallTimeWorker thread error. " \
                "Operation: #{operation_name} Cause: #{e.class}: #{e.message} Location: #{Array(e.backtrace).first}",
              )
              on_failure_proc&.call
              Datadog::Core::Telemetry::Logger.report(e, description: "CpuAndWallTimeWorker thread error: #{operation_name}")
            end
            @worker_thread.name = self.class.name # Repeated from above to make sure thread gets named asap
            @worker_thread.thread_variable_set(:fork_safe, true)
          end

          true
        end

        #: () -> void
        def stop
          @start_stop_mutex.synchronize do
            Datadog.logger.debug("Requesting CpuAndWallTimeWorker thread shut down")

            @idle_sampling_helper.stop
            @miteruby_consumer_enabled = false
            stop_miteruby_consumer
            if (hooks = @miteruby_fork_hooks)
              hooks.each { |stage, callback| Core::Utils::AtForkMonkeyPatch.remove_at_fork(stage, callback) }
              @miteruby_fork_hooks = nil
            end

            return unless @worker_thread

            self.class._native_stop(self, @worker_thread)

            @worker_thread.join
            @worker_thread = nil
            @worker_state.reset!
          end
        end

        #: () -> (StackRecorder | Miteruby::Serializer)
        def prepare_serialize
          miteruby_serializer = @miteruby_serializer
          return self.class._native_prepare_serialize(self) unless miteruby_serializer

          self.class._native_miteruby_consumer_prepare_serialize(miteruby_serializer)
          Datadog.logger.info("Serializing with miteruby!")
          miteruby_serializer
        end

        #: () -> true
        def reset_after_fork
          @start_stop_mutex.synchronize do
            if @miteruby_pid == Process.pid
              @miteruby_serializer&.reset_after_fork
            else
              reset_miteruby_after_fork
            end
            self.class._native_reset_after_fork(self)
          end
        end

        #: () -> ::Hash[::Symbol, untyped]
        def stats
          self.class._native_stats(self)
        end

        #: () -> ::Hash[::Symbol, untyped]
        def stats_and_reset_not_thread_safe
          stats = self.stats
          self.class._native_stats_reset_not_thread_safe(self)
          stats
        end

        # Useful for testing, to e.g. make sure the profiler is running before we start running some code we want to observe
        # @rbs timeout_seconds: ::Integer?
        # @rbs return: true
        def wait_until_running(timeout_seconds: 5)
          result = @worker_state.wait(timeout_seconds)
          case result
          when :running
            true
          when Exception
            raise "#{self.class.name} failed to start: #{result.class}: #{result.message}"
          else
            raise "Timeout waiting for #{self.class.name} to start (waited for #{timeout_seconds} seconds)"
          end
        end

        # Unlike wait_until_running, returns the failure instead of raising, and nil when the worker runs or
        # doesn't start on time.
        # @rbs timeout_seconds: Integer
        # @rbs return: Exception?
        def wait_for_start_or_failure(timeout_seconds:)
          result = @worker_state.wait(timeout_seconds)
          result if result.is_a?(Exception)
        end

        private

        # @rbs return: void
        def register_miteruby_fork_hooks
          return unless @miteruby_serializer
          return if @miteruby_fork_hooks

          Core::Utils::AtForkMonkeyPatch.apply!
          @miteruby_fork_hooks = Core::Utils::AtForkMonkeyPatch.at_fork_blocks(
            before: proc do
              @start_stop_mutex.synchronize do
                if @miteruby_fork_depth.zero?
                  @miteruby_consumer_enabled = @miteruby_consumer_thread&.alive? || false
                end
                @miteruby_fork_depth += 1
                stop_miteruby_consumer
              end
            end,
            parent: proc do
              @start_stop_mutex.synchronize do
                @miteruby_fork_depth -= 1
                @miteruby_consumer_thread = create_miteruby_consumer if @miteruby_consumer_enabled
              end
            end,
            child: proc do
              @start_stop_mutex.synchronize { reset_miteruby_after_fork }
            end,
          )
        end

        # @rbs return: void
        def stop_miteruby_consumer
          @miteruby_consumer_thread&.kill
          @miteruby_consumer_thread&.join
          @miteruby_consumer_thread = nil
        end

        # The profiler's child hook may restart us before our own child hook runs.
        # @rbs return: void
        def reset_miteruby_after_fork
          serializer = @miteruby_serializer
          return unless serializer

          self.class._native_miteruby_reset_after_fork
          return if @miteruby_pid == Process.pid

          serializer.reset_after_fork
          @miteruby_consumer_thread = nil
          @miteruby_fork_depth = 0
          @miteruby_pid = Process.pid
        end

        #: () -> Exception?
        def failure_exception
          @worker_state.failure
        end

        # @rbs return: Thread?
        def create_miteruby_consumer
          return unless @miteruby_serializer
          return unless @miteruby_fork_depth.zero?
          return @miteruby_consumer_thread if @miteruby_consumer_thread&.alive?

          thread_name = "#{self.class.name}::MiterubyConsumer"
          thread = Thread.new do
            Thread.current.name = thread_name
            self.class._native_miteruby_consumer_consume_loop
          rescue Exception => e # rubocop:disable Lint/RescueException
            @worker_state.failed!(e)
            Datadog.logger.warn(
              "Miteruby consumer thread error. " \
              "Cause: #{e.class}: #{e.message} Location: #{Array(e.backtrace).first}",
            )
            Datadog::Core::Telemetry::Logger.report(e, description: "Miteruby consumer thread error")
          end
          thread.name = thread_name
          thread.thread_variable_set(:fork_safe, true)
          thread
        end

        #: () -> void
        def signal_running
          @worker_state.running!
        end
      end
    end
  end
end
