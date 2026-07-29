# frozen_string_literal: true

module Datadog
  module Tracing
    module Transport
      # Shared agent capability negotiation for span event wire formats.
      module SpanEvents
        private

        def native_events_supported?
          return @native_events_supported if defined?(@native_events_supported)

          option = Datadog.configuration.tracing.native_span_events
          unless option.nil?
            @native_events_supported = option
            return option
          end

          response = Datadog.send(:components).agent_info.fetch
          return false unless response

          @native_events_supported = response.span_events == true
        end
      end
    end
  end
end
