# frozen_string_literal: true

require_relative 'ext'
require_relative 'binding/resolution_details'

module Datadog
  module OpenFeature
    # This class is a noop interface of evaluation logic
    class NoopEvaluator
      def initialize(_configuration)
        # no-op
      end

      def get_assignment(_flag_key, _evaluation_context, _expected_type)
        Binding::ResolutionDetails.new(
          error_code: Ext::PROVIDER_NOT_READY,
          error_message: 'Waiting for universal flag configuration',
          reason: Ext::INITIALIZING,
          flag_metadata: {},
          extra_logging: {},
          do_log: false
        )
      end
    end
  end
end
