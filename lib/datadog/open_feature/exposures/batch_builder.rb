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
            exposures: events.map(&:to_h)
          }
        end

        private

        def build_context(settings)
          env = extract_env(settings)
          service = extract_service(settings)
          version = extract_version(settings)

          context = {}
          context[:env] = env if env
          context[:service] = service if service
          context[:version] = version if version

          context
        end

        def extract_env(settings)
          return settings.env if settings.respond_to?(:env)
          return settings.tags['env'] if settings.respond_to?(:tags)

          nil
        end

        def extract_service(settings)
          return settings.service if settings.respond_to?(:service)
          return settings.tags['service'] if settings.respond_to?(:tags)

          nil
        end

        def extract_version(settings)
          return settings.version if settings.respond_to?(:version)
          return settings.tags['version'] if settings.respond_to?(:tags)

          nil
        end
      end
    end
  end
end
