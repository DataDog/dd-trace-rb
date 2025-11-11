# frozen_string_literal: true

require_relative '../../core/buffer/cruby'

module Datadog
  module OpenFeature
    module Exposures
      # This class is a buffer for exposure events that evicts at random and
      # keeps track of the number of dropped events
      class Buffer < Core::Buffer::CRuby
        DEFAULT_LIMIT = 1_000

        def initialize(limit = DEFAULT_LIMIT)
          @dropped = 0

          super
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
