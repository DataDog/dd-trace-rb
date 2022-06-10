require 'datadog/core/telemetry/utils/validation'

module Datadog
  module Core
    module Telemetry
      module V1
        # Describes attributes for integration object
        class Integration
          include Telemetry::Utils::Validation

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

          # @param enabled [Boolean] Whether integration is enabled at time of request
          # @param name [String] Integration name
          # @param auto_enabled [Boolean] If integration is not enabled by default, but by user choice
          # @param compatible [Boolean] If integration is available, but incompatible
          # @param error [String] Error message if integration fails to load
          # @param version [String] Integration version (if specified in app-started, it should be for other events too)
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

          # Validates all arguments passed to the class on initialization
          #
          # @!visibility private
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
