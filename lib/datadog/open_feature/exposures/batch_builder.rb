# frozen_string_literal: true

module Datadog
  module OpenFeature
    module Exposures
      # This class builds a batch of exposures and context to be sent to the Agent
      class BatchBuilder
        def initialize(settings)
          @context = build_context(settings)
        end

        def payload_for(events)
          {
            context: @context,
            exposures: events
          }
        end

        private

        def build_context(settings)
          context = {}
          context[:env] = settings.env if settings.env
          context[:service] = settings.service if settings.service
          context[:version] = settings.version if settings.version

          context
        end
      end
    end
  end
end
