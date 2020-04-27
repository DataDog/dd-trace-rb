require 'ddtrace/logger'

module Datadog
  module Workers
    module Async
      # Adds threading behavior to workers
      # to run tasks asynchronously.
      # rubocop:disable Metrics/ModuleLength
      module Thread
        FORK_POLICY_STOP = :stop
        FORK_POLICY_RESTART = :restart
        SHUTDOWN_TIMEOUT = 1

        def self.included(base)
          base.send(:prepend, PrependedMethods)
        end

        # Methods that must be prepended
        module PrependedMethods
          def perform(*args)
            start_async { self.result = super(*args) } unless started?
          end
        end

        attr_reader \
          :error,
          :result

        attr_writer \
          :fork_policy

        def join(timeout = nil)
          return true unless running?
          !worker.join(timeout).nil?
        end

        def terminate
          return false unless running?
          @run_async = false
          worker.terminate
          true
        end

        def run_async?
          @run_async = false unless instance_variable_defined?(:@run_async)
          @run_async == true
        end

        def started?
          !(worker.nil? || forked?)
        end

        def running?
          !worker.nil? && worker.alive?
        end

        def error?
          @error = nil unless instance_variable_defined?(:@error)
          !@error.nil?
        end

        def completed?
          !worker.nil? && worker.status == false && !error?
        end

        def failed?
          !worker.nil? && worker.status.nil?
        end

        def forked?
          !pid.nil? && pid != Process.pid
        end

        def fork_policy
          @fork_policy ||= FORK_POLICY_STOP
        end

        protected

        attr_writer \
          :result

        def mutex
          @mutex ||= Mutex.new
        end

        def after_fork
          # Do nothing by default
        end

        private

        attr_reader \
          :pid

        def mutex_after_fork
          @mutex_after_fork ||= Mutex.new
        end

        def worker
          @worker ||= nil
        end

        def start_async(&block)
          mutex.synchronize do
            return if running?
            if forked?
              case fork_policy
              when FORK_POLICY_STOP
                stop_fork
              when FORK_POLICY_RESTART
                restart_after_fork(&block)
              end
            elsif !run_async?
              start_worker(&block)
            end
          end
        end

        def start_worker
          @run_async = true
          @pid = Process.pid
          @error = nil
          Datadog.logger.debug("Starting thread in the process: #{Process.pid}")

          @worker = ::Thread.new do
            begin
              yield
            # rubocop:disable Lint/RescueException
            rescue Exception => e
              @error = e
              Datadog.logger.debug("Worker thread error. Cause #{e.message} Location: #{e.backtrace.first}")
              raise
            end
          end
        end

        def stop_fork
          mutex_after_fork.synchronize do
            if forked?
              # Trigger callback to allow workers to reset themselves accordingly
              after_fork

              # Reset and turn off
              @pid = Process.pid
              @run_async = false
            end
          end
        end

        def restart_after_fork(&block)
          mutex_after_fork.synchronize do
            if forked?
              # Trigger callback to allow workers to reset themselves accordingly
              after_fork

              # Start worker
              start_worker(&block)
            end
          end
        end
      end
    end
  end
end
