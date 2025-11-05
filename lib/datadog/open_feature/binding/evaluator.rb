# frozen_string_literal: true

require_relative 'resolution_details'

module Datadog
  module OpenFeature
    module Binding
      class Evaluator
        def initialize(ufc_json)
          # NOTE: In real binding we will parse and create Configuration
          @ufc_json = ufc_json
        end

        def get_assignment(_configuration, _flag_key, _evaluation_context, expected_type, _time, _default_value)
          ResolutionDetails.new(
            value: generate(expected_type),
            reason: 'TARGETING_MATCH',
            variant: 'hardcoded-variant',
            allocation_key: 'hardcoded-allocation-key',
            flag_metadata: {
              'doLog' => true,
              'allocationKey' => 'hardcoded-allocation-key'
            },
            do_log: true,
            extra_logging: {}
          )
        end

        private

        def generate(expected_type)
          case expected_type
          when :boolean then true
          when :string then 'hello'
          when :number then 9000
          when :integer then 42
          when :float then 36.6
          when :object then [1, 2, 3]
          end
        end
      end
    end
  end
end
