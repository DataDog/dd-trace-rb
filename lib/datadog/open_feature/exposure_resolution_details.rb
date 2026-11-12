# frozen_string_literal: true

require "open_feature/sdk"

module Datadog
  module OpenFeature
    class ExposureResolutionDetails < ::OpenFeature::SDK::Provider::ResolutionDetails
      attr_writer :exposure_callback

      def report_exposures
        callback = @exposure_callback
        @exposure_callback = nil
        callback&.call
      end
    end
  end
end
