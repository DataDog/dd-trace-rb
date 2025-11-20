# frozen_string_literal: true

require 'json'
require_relative '../core/feature_flags'
require_relative 'ext'
require_relative 'resolution_details'

module Datadog
  module OpenFeature
    # Evaluation using native extension
    class NativeEvaluator
      def initialize(configuration)
        @configuration = Datadog::Core::FeatureFlags::Configuration.new(configuration)
      end

      def get_assignment(flag_key, default_value, context, expected_type)
        native_details = @configuration.get_assignment(flag_key, expected_type.to_sym, context)

        variant = native_details.variant
        value = native_details.value
        if expected_type == 'object' && value.is_a?(String)
          # JSON flags return value as string. We need to parse it.
          value = JSON.parse(value)
        elsif variant.nil?
          value = default_value
        end

        ResolutionDetails.new(
          value: value,
          variant: variant,
          allocation_key: native_details.allocation_key,
          reason: native_details.reason,
          error?: native_details.error?,
          error_code: native_details.error_code,
          error_message: native_details.error_message,
          log?: native_details.log?,
          flag_metadata: native_details.flag_metadata,
          extra_logging: {},
        )
      rescue JSON::ParserError => e
        ResolutionDetails.build_error(
          value: default_value,
          error_code: 'PARSE_ERROR',
          error_message: "Failed to parse JSON value: #{e.message}"
        )
      end
    end
  end
end
