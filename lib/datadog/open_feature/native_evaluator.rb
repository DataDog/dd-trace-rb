# frozen_string_literal: true

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
        @observe_full_evaluation_data = @configuration.observe_full_evaluation_data
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
      # @return [ResolutionDetails] The assignment for the flag
      def get_assignment(flag_key, default_value:, expected_type:, context:)
        result = @configuration.get_assignment(flag_key, expected_type, context)

        return invalid_flag_configuration_error(default_value) if invalid_flag_configuration?(result)

        value = result.variant.nil? ? default_value : result.value
        details = build_resolution_details(result, value)
        dependencies = result.respond_to?(:dependency_evaluations) ? result.dependency_evaluations : []
        details.dependency_evaluations = dependencies.map do |key, dependency, eligible|
          [key, build_dependency_resolution_details(dependency), eligible]
        end
        details
      end

      private

      def build_dependency_resolution_details(result)
        if result.variant.nil? && (result.reason == "DISABLED" || result.reason == Ext::DEFAULT)
          return ResolutionDetails.new(
            value: nil,
            reason: Ext::ERROR,
            error_code: Ext::GENERAL,
            error_message: "prerequisite has no assignment",
            error?: true,
            log?: false,
          )
        end

        build_resolution_details(result, nil)
      end

      def build_resolution_details(result, value)
        ResolutionDetails.new(
          value: value,
          reason: result.reason,
          variant: result.variant,
          error_code: result.error_code,
          error_message: result.error_message,
          flag_metadata: result.flag_metadata,
          allocation_key: result.allocation_key,
          serial_id: result.serial_id,
          log?: result.log?,
          error?: result.error?,
        )
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
          error_message: INVALID_FLAG_CONFIGURATION_ERROR_MESSAGE,
        )
      end
    end
  end
end
