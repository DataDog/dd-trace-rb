require 'datadog/core/telemetry/schemas/utils/validation'

module Datadog
  module Core
    module Telemetry
      module Schemas
        module V1
          module Base
            # Describes attributes for integration object
            class Integration
              include Schemas::Utils::Validation

              ERROR_BAD_ENABLED_MESSAGE = ':enabled must be a non-nil Boolean'.freeze
              ERROR_BAD_NAME_MESSAGE = ':name must be a non-empty String'.freeze
              ERROR_BAD_AUTO_ENABLED_MESSAGE = ':auto_enabled must be of type Boolean'.freeze
              ERROR_BAD_COMPATIBLE_MESSAGE = ':compatible must be of type Boolean'.freeze
              ERROR_BAD_ERROR_MESSAGE = ':error must be of type String'.freeze
              ERROR_BAD_VERSION_MESSAGE = ':version must be of type String'.freeze

              attr_reader \
                :auto_enabled,
                :compatible,
                :enabled,
                :error,
                :name,
                :version

              def initialize(enabled:, name:, auto_enabled: nil, compatible: nil, error: nil, version: nil)
                validate(auto_enabled: auto_enabled, compatible: compatible, enabled: enabled, error: error, name: name,
                         version: version)
                @auto_enabled = auto_enabled
                @compatible = compatible
                @enabled = enabled
                @error = error
                @name = name
                @version = version
              end

              private

              def validate(auto_enabled:, compatible:, enabled:, error:, name:, version:)
                raise ArgumentError, ERROR_BAD_ENABLED_MESSAGE unless valid_bool?(enabled)
                raise ArgumentError, ERROR_BAD_NAME_MESSAGE unless valid_string?(name)
                raise ArgumentError, ERROR_BAD_AUTO_ENABLED_MESSAGE unless valid_optional_bool?(auto_enabled)
                raise ArgumentError, ERROR_BAD_COMPATIBLE_MESSAGE unless valid_optional_bool?(compatible)
                raise ArgumentError, ERROR_BAD_ERROR_MESSAGE unless valid_optional_string?(error)
                raise ArgumentError, ERROR_BAD_VERSION_MESSAGE unless valid_optional_string?(version)
              end
            end
          end
        end
      end
    end
  end
end
