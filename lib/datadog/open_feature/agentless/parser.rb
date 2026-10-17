# frozen_string_literal: true

require "json"

module Datadog
  module OpenFeature
    module Agentless
      # Parses the JSON:API envelope returned by agentless delivery.
      module Parser
        RESOURCE_TYPE = "universal-flag-configuration"

        module_function

        def parse(body)
          payload = JSON.parse(body)
          return unless payload.is_a?(Hash)

          data = payload["data"]
          return unless data.is_a?(Hash) && data["type"] == RESOURCE_TYPE

          attributes = data["attributes"]
          return unless valid_attributes?(attributes)

          JSON.generate(attributes)
        rescue JSON::ParserError, JSON::GeneratorError, TypeError
          nil
        end

        def valid_attributes?(attributes)
          return false unless attributes.is_a?(Hash)

          environment = attributes["environment"]
          attributes["format"].is_a?(String) &&
            attributes["createdAt"].is_a?(String) &&
            environment.is_a?(Hash) &&
            environment["name"].is_a?(String) &&
            attributes["flags"].is_a?(Hash)
        end
        private_class_method :valid_attributes?
      end
    end
  end
end
