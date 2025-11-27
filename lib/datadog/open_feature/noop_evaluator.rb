# frozen_string_literal: true

require_relative 'ext'
require_relative 'resolution_details'

module Datadog
  module OpenFeature
    # This class is a noop interface of evaluation logic
    class NoopEvaluator
      def initialize(_configuration)
        # no-op
      end

      def get_assignment(_flag_key, default_value:, context:, expected_type:)
        ResolutionDetails.new(
          value: default_value,
          log?: false,
          error?: true,
          error_code: Ext::PROVIDER_NOT_READY,
          error_message: 'Waiting for flags configuration',
          reason: Ext::ERROR
        )
      end
    end
  end
end
