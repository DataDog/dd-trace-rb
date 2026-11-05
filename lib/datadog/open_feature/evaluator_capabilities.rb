# frozen_string_literal: true

module Datadog
  module OpenFeature
    module EvaluatorCapabilities
      DEPENDENT_FLAG_VARIANT_KEY_V1 = "dependent-flag-variant-key-v1"

      # Opt-in requires native evaluation, error propagation, and exposure support.
      def self.supported
        []
      end
    end
  end
end
