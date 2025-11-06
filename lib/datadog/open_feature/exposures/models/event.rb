# frozen_string_literal: true

require_relative '../../../core/utils/time'

module Datadog
  module OpenFeature
    module Exposures
      module Models
        # A data model for an exposure event
        class Event
          TARGETING_KEY_FIELD = 'targeting_key'
          ALLOWED_FIELD_TYPES = [
            String,
            Integer,
            Float,
            TrueClass,
            FalseClass
          ].freeze

          # NOTE: The result is a Hash-like structure like this
          #
          # {
          #     "flag": "boolean-one-of-matches",
          #     "variationType": "INTEGER",
          #     "defaultValue": 0,
          #     "targetingKey": "haley",
          #     "attributes": {
          #       "not_matches_flag": "False"
          #     },
          #     "result": {
          #       "value": 4,
          #       "variant": "4",
          #       "flagMetadata": {
          #         "allocationKey": "4-for-not-matches",
          #         "variationType": "number",
          #         "doLog": true
          #       }
          #     }
          # }
          class << self
            def build(result, context:)
              payload = {
                timestamp: current_timestamp_ms,
                allocation: {
                  key: result.dig('result', 'flagMetadata', 'allocationKey').to_s
                },
                flag: {
                  key: result['flag'].to_s
                },
                variant: {
                  key: result.dig('result', 'variant').to_s
                },
                subject: {
                  id: result['targetingKey'].to_s,
                  attributes: extract_attributes(context)
                }
              }

              new(payload)
            end

            private

            def extract_attributes(context)
              context.fields.select do |key, value|
                next false if key == TARGETING_KEY_FIELD
                next true if ALLOWED_FIELD_TYPES.include?(value.class)

                false
              end
            end

            def current_timestamp_ms
              (Datadog::Core::Utils::Time.now.to_f * 1000).to_i
            end
          end

          def initialize(payload)
            @payload = payload
          end

          def flag_key
            @payload.dig(:flag, :key).to_s
          end

          def targeting_key
            @payload.dig(:subject, :id).to_s
          end

          def allocation_key
            @payload.dig(:allocation, :key).to_s
          end

          def variation_key
            @payload.dig(:variant, :key).to_s
          end

          def to_h
            @payload
          end
        end
      end
    end
  end
end
