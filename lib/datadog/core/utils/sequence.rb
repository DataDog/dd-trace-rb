# frozen_string_literal: true

module Datadog
  module Core
    module Utils
      # Generates values from a consistent sequence
      class Sequence
        def initialize(seed = 0)
          @seed = seed
          @current = seed
        end

        def next
          current = @current
          @current += 1
          current
        end

        def reset!
          @current = @seed
        end
      end
    end
  end
end
