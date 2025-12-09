# frozen_string_literal: true

module Datadog
  module Core
    module Utils
      # Generates values from a consistent sequence
      class Sequence
        def initialize(seed = 0, &block)
          @seed = seed
          @current = seed
          @next_item = block
        end

        def next
          # Steep: https://github.com/soutaro/steep/issues/477
          next_item = @next_item ? @next_item.call(@current) : @current # steep:ignore NoMethod
          @current += 1
          next_item
        end

        def reset!
          @current = @seed
        end
      end
    end
  end
end
