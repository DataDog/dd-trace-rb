# typed: true

module Datadog
  module Core
    module Utils
      # Generates values from a consistent numeric sequence
      class SequenceNumeric
        def initialize(seed = 0, increment: 1)
          @seed = seed
          @increment = increment
          @current = seed
          @mutex = Mutex.new
        end

        def next
          @mutex.synchronize do
            next_item = @current
            @current += @increment
            next_item
          end
        end

        def reset!
          @mutex.synchronize do
            @current = @seed
          end
        end
      end
    end
  end
end
