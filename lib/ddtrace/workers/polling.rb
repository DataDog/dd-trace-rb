require 'ddtrace/workers/async'
require 'ddtrace/workers/loop'

module Datadog
  module Workers
    # Adds polling (async looping) behavior to workers
    module Polling
      SHUTDOWN_TIMEOUT = 1

      def self.included(base)
        base.send(:include, Workers::IntervalLoop)
        base.send(:include, Workers::Async::Thread)
        base.send(:prepend, PrependedMethods)
      end

      # Methods that must be prepended
      module PrependedMethods
        def perform(*args)
          super if enabled?
        end
      end

      def stop(force_stop = false, timeout = SHUTDOWN_TIMEOUT)
        if running?
          # Attempt graceful stop and wait
          stop_loop
          graceful = join(timeout)

          # If timeout and force stop...
          !graceful && force_stop ? terminate : graceful
        else
          false
        end
      end

      def enabled?
        return true unless instance_variable_defined?(:@enabled)
        @enabled
      end

      # Allow worker to be started
      def enabled=(value)
        # Coerce to boolean
        @enabled = (value == true)
      end
    end
  end
end
