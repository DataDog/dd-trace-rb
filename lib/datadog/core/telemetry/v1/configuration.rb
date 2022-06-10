require 'datadog/core/telemetry/utils/validation'

module Datadog
  module Core
    module Telemetry
      module V1
        # Describes attributes for additional payload or configuration object
        class Configuration
          include Telemetry::Utils::Validation

          ERROR_BAD_NAME_MESSAGE = ':name must be a non-empty string'.freeze
          ERROR_BAD_VALUE_MESSAGE = ':value must be of type String, Integer or Boolean'.freeze

          attr_reader \
            :name,
            :value

          # @param name [String] Configuration/additional payload attribute name
          # @param value [String, Integer, Boolean] Corresponding value
          def initialize(name:, value: nil)
            validate(name: name, value: value)
            @name = name
            @value = value
          end

          private

          # Validates all arguments passed to the class on initialization
          #
          # @!visibility private
          def validate(name:, value:)
            raise ArgumentError, ERROR_BAD_NAME_MESSAGE unless valid_string?(name)
            if value && !(valid_string?(value) || valid_bool?(value) || valid_int?(value))
              raise ArgumentError, ERROR_BAD_VALUE_MESSAGE
            end
          end
        end
      end
    end
  end
end
