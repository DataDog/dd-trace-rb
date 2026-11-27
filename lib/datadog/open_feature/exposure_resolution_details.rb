# frozen_string_literal: true

require "open_feature/sdk"

module Datadog
  module OpenFeature
    class ExposureResolutionDetails < ::OpenFeature::SDK::Provider::ResolutionDetails
      attr_writer :pending_exposures

      def take_exposures
        exposures = @pending_exposures || []
        @pending_exposures = nil
        exposures
      end
    end
  end
end
