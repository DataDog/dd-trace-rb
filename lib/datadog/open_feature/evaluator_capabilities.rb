# frozen_string_literal: true

require_relative "../core/feature_flags"

module Datadog
  module OpenFeature
    module EvaluatorCapabilities
      DEPENDENT_FLAG_VARIANT_KEY_V1 = "dependent-flag-variant-key-v1"

      def self.dependent_flags?
        return false unless Core::FeatureFlags.respond_to?(:evaluator_capabilities)

        Core::FeatureFlags.evaluator_capabilities.include?(DEPENDENT_FLAG_VARIANT_KEY_V1)
      # Discovery must never prevent configuration delivery when a native extension fails.
      rescue
        false
      end
    end
  end
end
