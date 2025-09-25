# frozen_string_literal: true

module Datadog
  module Core
    module Telemetry
      module Event
        # Telemetry class for the 'message-batch' event.
        class MessageBatch < Base
          attr_reader :events

          def type
            'message-batch'
          end

          def initialize(events)
            super()
            @events = events
          end

          def payload
            @events.map do |event|
              if event.type == 'app-endpoints'
                puts '*****'
                pp event.payload
                puts '*****'
              end

              {
                request_type: event.type,
                payload: event.payload,
              }
            end
          end

          def ==(other)
            other.is_a?(MessageBatch) && other.events == @events
          end

          alias_method :eql?, :==

          def hash
            [self.class, @events].hash
          end
        end
      end
    end
  end
end
