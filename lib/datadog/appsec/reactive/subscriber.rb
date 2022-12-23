# typed: ignore

module Datadog
  module AppSec
    module Reactive
      # Reactive Engine subscriber
      class Subscriber
        def initialize(&block)
          @block = block
        end

        def call(*args)
          @block.call(*args)
        end
      end
    end
  end
end
