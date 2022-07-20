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
        end

        def next
          next_item = @current
          @current += @increment
          next_item
        end

        def reset!
          @current = @seed
        end
      end
    end
  end
end
