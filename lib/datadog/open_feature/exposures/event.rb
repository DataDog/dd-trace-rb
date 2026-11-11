# frozen_string_literal: true

require_relative "../../core/utils/time"

module Datadog
  module OpenFeature
    module Exposures
      # A data model for an exposure event
      module Event
        TARGETING_KEY_FIELD = "targeting_key"
        ALLOWED_FIELD_TYPES = [String, Integer, Float, TrueClass, FalseClass].freeze

        class << self
          def cache_key(flag_key:, targeting_key:)
            "#{flag_key}:#{targeting_key}"
          end

          # NOTE: The serial id is part of the value because it can appear or change on a
          #       configuration refresh while the allocation and the variant stay the same.
          def cache_value(allocation_key:, variant:, serial_id:)
            "#{allocation_key}:#{variant}:#{serial_id}"
          end

          # Features stay out of the cache value: a features change alone is not a new exposure.
          def build(flag_key:, allocation_key:, variant:, serial_id:, context:, features:)
            # @type var event: t
            event = {
              timestamp: current_timestamp_ms,
              allocation: {
                key: allocation_key,
              },
              flag: {
                key: flag_key,
              },
              variant: {
                key: variant,
              },
              subject: {
                id: context.targeting_key,
                attributes: extract_attributes(context),
              },
            }

            event[:serial_id] = serial_id unless serial_id.nil?
            event[:features] = features unless features.empty?

            event.freeze
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
