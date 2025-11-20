# frozen_string_literal: true

require 'json'

module Datadog
  module Core
    # Feature flags evaluation using libdatadog
    # The classes in this module are defined as C extensions in ext/libdatadog_api/feature_flags.c
    module FeatureFlags
      # Configuration for feature flags evaluation
      # This class is defined in the C extension
      class Configuration # rubocop:disable Lint/EmptyClass
      end

      # Resolution details for a feature flag evaluation
      # Base class is defined in the C extension, with Ruby methods added here
      class ResolutionDetails
        # Get the resolved value, with JSON parsing for object types
        #
        # @return [Object] The resolved value (parsed from JSON if object type)
        # @raise [Datadog::Core::FeatureFlags::Error] If JSON parsing fails
        def value
          return @value if defined?(@value)

          val = raw_value

          # Parse JSON for object types
          if flag_type == :object && val.is_a?(String)
            begin
              val = JSON.parse(val)
            rescue JSON::ParserError => e
              raise Error, "Failed to parse JSON value: #{e.message}"
            end
          end

          @value = val
        end

        attr_writer :value
      end
    end
  end
end
