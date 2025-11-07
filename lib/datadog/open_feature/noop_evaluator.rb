# frozen_string_literal: true

require_relative 'ext'

module Datadog
  module OpenFeature
    # This class is a noop interface of evaluation logic
    class NoopEvaluator
      def initialize(_configuration)
        # no-op
      end

      def get_assignment(_flag_key, _evaluation_context, _expected_type, _timestamp)
        {
          error_code: Ext::PROVIDER_NOT_READY,
          error_message: 'Waiting for universal flag configuration',
          reason: Ext::INITIALIZING
        }
      end
    end
  end
end
