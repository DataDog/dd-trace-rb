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
        def run
          @mutex.synchronize do
            return if @ran_once

            result = yield
            @ran_once = !!result

            result
          end
        end
      end
    end
  end
end
