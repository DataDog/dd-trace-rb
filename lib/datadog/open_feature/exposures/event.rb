# frozen_string_literal: true

require_relative '../../core/utils/time'

module Datadog
  module OpenFeature
    module Exposures
      # A data model for an exposure event
      module Event
        TARGETING_KEY_FIELD = 'targeting_key'
        ALLOWED_FIELD_TYPES = [String, Integer, Float, TrueClass, FalseClass].freeze

        class << self
          def cache_key(result, flag_key:, context:)
            "#{flag_key}:#{context.targeting_key}"
          end

          def cache_value(result, flag_key:, context:)
            "#{result.allocation_key}:#{result.variant}"
          end

          def build(result, flag_key:, context:)
            {
              timestamp: current_timestamp_ms,
              allocation: {
                key: result.allocation_key
              },
              flag: {
                key: flag_key
              },
              variant: {
                key: result.variant
              },
              subject: {
                id: context.targeting_key,
                attributes: extract_attributes(context)
              }
            }.freeze
          end

          private

          # NOTE: We take all filds of the context that does not support nesting
          #       and will ignore targeting key as it will be set as `subject.id`
          def extract_attributes(context)
            context.fields.select do |key, value|
              next false if key == TARGETING_KEY_FIELD

              ALLOWED_FIELD_TYPES.include?(value.class)
            end
          end

          def current_timestamp_ms
            (Datadog::Core::Utils::Time.now.to_f * 1000).to_i
          end
        end
      end
    end
  end
end
