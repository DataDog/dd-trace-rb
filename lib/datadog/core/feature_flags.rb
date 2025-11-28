# frozen_string_literal: true

require 'json'

module Datadog
  module Core
    # Feature flags evaluation using libdatadog
    # The classes in this module are defined as C extensions in ext/libdatadog_api/feature_flags.c
    #
    # @api private
    module FeatureFlags
      # A top-level error raised by the extension
      class Error < StandardError # rubocop:disable Lint/EmptyClass
      end

      # Configuration for feature flags evaluation
      # This class is defined in the C extension
      class Configuration # rubocop:disable Lint/EmptyClass
      end

      # Resolution details for a feature flag evaluation
      # Base class is defined in the C extension, with Ruby methods added here
      class ResolutionDetails
        attr_writer :value

        # Get the resolved value, with JSON parsing for object types
        #
        # @return [Object] The resolved value (parsed from JSON if object type)
        # @raise [Datadog::Core::FeatureFlags::Error] If JSON parsing fails
        def value
          return @value if defined?(@value)

          # NOTE: Raw value method call doesn't support memoization right now
          value = raw_value

          # NOTE: Lazy parsing of the JSON is a temporary solution and will be
          #       moved into C extension
          @value = json?(value) ? JSON.parse(value) : value
        rescue JSON::ParserError => e
          raise Error, "Failed to parse JSON value: #{e.class}: #{e}"
        end

        # Check if the resolution resulted in an error
        #
        # @return [Boolean] True if there was an error
        def error?
          reason == 'ERROR'
        end

        private

        # NOTE: A JSON raw string will be returned by the `libdatadog` as
        #       a Ruby String class with a flag type `:object`, otherwise it's
        #       just a string.
        def json?(value)
          flag_type == :object && value.is_a?(String)
        end
      end
    end
  end
end
