# frozen_string_literal: true

module Datadog
  module OpenFeature
    module Binding
      class InternalEvaluator
        def initialize(ufc_json)
          @ufc_json = ufc_json
        end

        def get_assignment(_configuration, _flag_key, _evaluation_context, expected_type, _time)
          # TODO: Implement actual evaluation logic
          # For now, return mock ResolutionDetails to maintain compatibility
          ResolutionDetails.new(
            value: generate_mock_value(expected_type),
            reason: 'mock_internal',
            variant: 'mock_variant',
            flag_metadata: {
              'allocationKey' => 'mock_allocation',
              'doLog' => true,
              'variationType' => expected_type.to_s
            }
          )
        end

        private

        def generate_mock_value(expected_type)
          case expected_type
          when :boolean then true
          when :string then 'internal_mock'
          when :number then 42
          when :integer then 42
          when :float then 3.14
          when :object then { 'mock' => 'data' }
          else 'unknown_type'
          end
        end
      end
    end
  end
end