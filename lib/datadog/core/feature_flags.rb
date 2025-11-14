# frozen_string_literal: true

module Datadog
  module Core
    # Feature flags evaluation using libdatadog
    # The classes in this module are defined as C extensions in ext/libdatadog_api/feature_flags.c
    module FeatureFlags
      # Configuration for feature flags evaluation
      # This class is defined in the C extension
      class Configuration
      end

      # Resolution details for a feature flag evaluation
      # This class is defined in the C extension
      class ResolutionDetails
      end
    end
  end
end
