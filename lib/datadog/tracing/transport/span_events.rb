# frozen_string_literal: true

module Datadog
  module Tracing
    module Transport
      # Shared agent capability negotiation for span event wire formats.
      module SpanEventsNegotiation
        private

        # Queries whether the agent accepts typed span events, which selects
        # between the typed field and legacy JSON metadata. Only successful
        # capability responses are cached so a later flush can recover.
        #
        # The memo is read and written without synchronization, independent of
        # any lock the including transport holds for its own sends (the native
        # transport's +@send_mutex+, for example). Two concurrent sends can both
        # observe it unset and each issue an +agent_info.fetch+; the duplicate
        # fetch is self-correcting (the last writer wins) and cheaper than
        # serializing every send behind the capability lookup.
        #
        # @return [Boolean] true if typed span events are supported
        def native_events_supported?
          return @native_events_supported if defined?(@native_events_supported)

          option = Datadog.configuration.tracing.native_span_events
          unless option.nil?
            @native_events_supported = option
            return option
          end

          components = Datadog.send(:components, allow_initialization: false)
          return false unless components

          response = components.agent_info.fetch
          return false unless response

          @native_events_supported = response.span_events == true
        end
      end
    end
  end
end
