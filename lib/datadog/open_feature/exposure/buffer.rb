# frozen_string_literal: true

module Datadog
  module OpenFeature
    module Exposure
      class Buffer
        attr_reader :events

        def initialize
          @events = []
        end

        def push(event)
          events << event
        end

        def empty?
          events.empty?
        end

        def drain
          current = events.dup
          events.clear
          current
        end

        private

        attr_reader :events
      end
    end
  end
end
