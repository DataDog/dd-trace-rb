# frozen_string_literal: true

require_relative '../../core/buffer/cruby'

module Datadog
  module OpenFeature
    module Exposures
      # This class is a buffer for exposure events that evicts at random and
      # keeps track of the number of dropped events
      #
      # WARNING: This class does not work as intended on JRuby
      class Buffer < Core::Buffer::CRuby
        DEFAULT_LIMIT = 1_000

        attr_reader :dropped_count

        def initialize(limit = DEFAULT_LIMIT)
          @dropped = 0
          @dropped_count = 0

          super
        end

        protected

        def drain!
          drained = super

          @dropped_count = @dropped
          @dropped = 0

          drained
        end

        def replace!(item)
          @dropped += 1

          super
        end
      end
    end
  end
end
