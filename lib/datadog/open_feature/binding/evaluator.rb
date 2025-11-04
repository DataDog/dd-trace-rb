module Datadog
  module OpenFeature
    module Binding
      ResolutionDetails = Struct.new(
        :value,
        :reason,
        :variant,
        :error_code,
        :error_message,
        :flag_metadata,
        keyword_init: true
      )

      class Evaluator
        def initialize(ufc_json)
          # NOTE: In real binding we will parse and create Configuration
          @ufc_json = ufc_json
        end

        def get_assignment(_configuration, _flag_key, _evaluation_context, expected_type, _time)
          ResolutionDetails.new(
            value: generate(expected_type),
            reason: 'hardcoded',
            variant: 'hardcoded'
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
