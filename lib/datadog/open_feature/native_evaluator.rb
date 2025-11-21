# frozen_string_literal: true

require_relative '../core/feature_flags'

module Datadog
  module OpenFeature
    # This class is an interface of evaluation logic using native extension
    class NativeEvaluator
      def initialize(configuration)
        @configuration = Core::FeatureFlags::Configuration.new(configuration)
      end

      def get_assignment(flag_key, default_value, context, expected_type)
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
