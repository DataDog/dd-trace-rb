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

        protected

        def drain!
          drained = super
          dropped = @dropped
          @dropped = 0
          [drained, dropped]
        end

        def replace!(item)
          @dropped += 1
          super
        end
      end
    end
  end
end
