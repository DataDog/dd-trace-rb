# frozen_string_literal: true

require_relative 'only_once'

module Datadog
  module Core
    module Utils
      # Helper class to execute something with only one success.
      #
      # This is useful for cases where we want to ensure that a block of code is only executed once, and only if it
      # succeeds. One such example is sending app-started telemetry event.
      #
      # Successful execution is determined by the return value of the block: any truthy value is considered success.
      #
      # Thread-safe when used correctly (e.g. be careful of races when lazily initializing instances of this class).
      #
      # Note: In its current state, this class is not Ractor-safe.
      # In https://github.com/DataDog/dd-trace-rb/pull/1398#issuecomment-797378810 we have a discussion of alternatives,
      # including an alternative implementation that is Ractor-safe once spent.
      class OnlyOnceSuccessful < OnlyOnce
        def initialize(limit = 0)
          super()

          @limit = limit
          @failed = false
          @retries = 0
        end

        def run
          @mutex.synchronize do
            return if @ran_once

            result = yield
            @ran_once = !!result

            if !@ran_once && limited?
              @retries += 1
              check_limit!
            end

            result
          end
        end

        def success?
          @mutex.synchronize { @ran_once && !@failed }
        end

        def failed?
          @mutex.synchronize { @ran_once && @failed }
        end

        private

        def check_limit!
          if @retries >= @limit
            @failed = true
            @ran_once = true
          end
        end

        def limited?
          !@limit.nil? && @limit.positive?
        end
      end
    end
  end
end
