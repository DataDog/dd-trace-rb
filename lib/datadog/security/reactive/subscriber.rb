module Datadog
  module Security
    module Reactive
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
