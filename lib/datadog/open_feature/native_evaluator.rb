# frozen_string_literal: true

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
        native_details = @configuration.get_assignment(flag_key, expected_type, context)

        native_details.value = default_value if native_details.variant.nil?

        native_details
      end
    end
  end
end
