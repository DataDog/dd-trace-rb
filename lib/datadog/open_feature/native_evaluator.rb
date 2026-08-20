# frozen_string_literal: true

require "json"
require_relative "../core/feature_flags"
require_relative "ext"
require_relative "resolution_details"

module Datadog
  module OpenFeature
    # This class is an interface of evaluation logic using native extension
    class NativeEvaluator
      INVALID_FLAG_CONFIGURATION_ERROR_MESSAGE = "flag configuration is invalid or unsupported"

      # NOTE: In a currect implementation configuration is expected to be a raw
      #       JSON string containing feature flags (straight from the remote config)
      #       in the format expected by `libdatadog` without any modifications
      def initialize(configuration)
        @configuration = Core::FeatureFlags::Configuration.new(configuration)
        @observe_full_evaluation_data = parse_observe_full_evaluation_data(configuration)
      end

      attr_reader :observe_full_evaluation_data

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

        return invalid_flag_configuration_error(default_value) if invalid_flag_configuration?(result)

        # NOTE: This is a special case when we need to fallback to the default
        #       value, even tho the evaluation itself doesn't produce an error
        #       resolution details
        result.value = default_value if result.variant.nil?
        result
      end

      private

      # Parse observe_full_evaluation_data from the top level of the UFC JSON (a sibling
      # of `environment`). Absent, null, or wrong-typed values return false.
      # Malformed JSON returns false without raising: the C extension owns the
      # full UFC parse and raises on truly bad input, so this read must
      # never be what strands a pod on PROVIDER_NOT_READY.
      def parse_observe_full_evaluation_data(configuration)
        return false unless configuration.is_a?(String) && !configuration.empty?

        parsed = JSON.parse(configuration)
        parsed.is_a?(Hash) && parsed["observeFullEvaluationData"] == true
      rescue
        # Deliberately broad (bare rescue catches StandardError): this cosmetic read
        # must never reject a UFC that the C extension accepts, so any failure here
        # falls to the safe default.
        false
      end

      def invalid_flag_configuration?(result)
        result.reason == Ext::DEFAULT &&
          result.error_code.nil? &&
          result.error_message == INVALID_FLAG_CONFIGURATION_ERROR_MESSAGE
      end

      def invalid_flag_configuration_error(default_value)
        ResolutionDetails.build_error(
          value: default_value,
          error_code: Ext::PARSE_ERROR,
          error_message: INVALID_FLAG_CONFIGURATION_ERROR_MESSAGE
        )
      end
    end
  end
end
