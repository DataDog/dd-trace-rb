# frozen_string_literal: true

require_relative '../../core/utils/time'

module Datadog
  module OpenFeature
    module Exposures
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

        class << self
          def build(result, flag_key:, context:)
            payload = {
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
            }

            new(payload)
          end

          private

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

        def initialize(payload)
          @payload = payload.freeze
        end

        def flag_key
          @payload.dig(:flag, :key)
        end

        def targeting_key
          @payload.dig(:subject, :id)
        end

        def allocation_key
          @payload.dig(:allocation, :key)
        end

        def variation_key
          @payload.dig(:variant, :key)
        end

        def to_h
          @payload
        end
      end
    end
  end
end
