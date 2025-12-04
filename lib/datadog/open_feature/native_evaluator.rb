# frozen_string_literal: true

require_relative '../core/feature_flags'

module Datadog
  module OpenFeature
    # This class is an interface of evaluation logic using native extension
    class NativeEvaluator
      # NOTE: In a currect implementation configuration is expected to be a raw
      #       JSON string containing feature flags (straight from the remote config)
      #       in the format expected by `libdatadog` without any modifications
      def initialize(configuration)
        @configuration = Core::FeatureFlags::Configuration.new(configuration)
      end

      # Returns the assignment for a given flag key based on the feature flags
      # configuration
      #
      # @param flag_key [String] The key of the feature flag
      # @param default_value [Object] The default value to return if the flag is
      #                              not found or evaluation itself fails
      # @param expected_type [Symbol] The expected type of the flag
      # @param context [Hash] The context of the evaluation, containing targeting key
      #                       and other attributes
      #
      # @return [Core::FeatureFlags::ResolutionDetails] The assignment for the flag
      def get_assignment(flag_key, default_value:, expected_type:, context:)
        result = @configuration.get_assignment(flag_key, expected_type, context)

        # NOTE: This is a special case when we need to fallback to the default
        #       value, even tho the evaluation itself doesn't produce an error
        #       resolution details
        result.value = default_value if result.variant.nil?
        result
      end
    end
  end
end
