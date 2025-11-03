# frozen_string_literal: true

require_relative '../../core/buffer/thread_safe'

module Datadog
  module OpenFeature
    module Exposures
      class Buffer < Datadog::Core::Buffer::ThreadSafe
        DEFAULT_LIMIT = 1000

        def initialize(limit = DEFAULT_LIMIT)
          super(limit)
          @dropped = 0
        end

        def size
          length
        end

        def limit
          @max_size
        end

        def full?
          synchronize { full_without_sync? }
        end

        def drain
          synchronize do
            drained = @items
            dropped = @dropped
            @items = []
            @dropped = 0
            [drained, dropped]
          end
        end

        private

        def replace!(item)
          @dropped += 1
          super
        end

        def full_without_sync?
          @max_size.positive? && @items.length >= @max_size
        end
      end
    end
  end
end
