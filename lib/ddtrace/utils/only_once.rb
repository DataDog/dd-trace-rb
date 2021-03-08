# frozen_string_literal: true

module Datadog
  module Utils
    # Helper class to execute something only once such as not repeating warning logs, and instrumenting classes
    # only once.
    #
    # Thread-safe when used correctly (e.g. be careful of races when lazily initializing instances of this class).
    class OnlyOnce
      def initialize
        @mutex = Mutex.new
        @ran_once = false
      end

      def run
        @mutex.synchronize do
          return if @ran_once

          @ran_once = true

          yield
        end
      end

      def ran?
        @mutex.synchronize { @ran_once }
      end

      private

      def reset_ran_once_state_for_tests
        @mutex.synchronize { @ran_once = false }
      end
    end
  end
end
