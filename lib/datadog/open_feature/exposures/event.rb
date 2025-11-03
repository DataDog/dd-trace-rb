# frozen_string_literal: true

module Datadog
  module OpenFeature
    module Exposures
      class Event
        attr_reader :timestamp,
          :allocation_key,
          :flag_key,
          :variant_key,
          :subject_id,
          :subject_type,
          :subject_attributes

        def initialize(
          timestamp:, allocation_key:, flag_key:, variant_key:, subject_id:, subject_type: nil,
          subject_attributes: nil
        )
          @timestamp = normalize_timestamp(timestamp)
          @allocation_key = allocation_key
          @flag_key = flag_key
          @variant_key = variant_key
          @subject_id = subject_id
          @subject_type = subject_type
          @subject_attributes = sanitize_attributes(subject_attributes)
          validate_required_fields
        end

        def to_h
          {
            timestamp: timestamp,
            allocation: { key: allocation_key },
            flag: { key: flag_key },
            variant: { key: variant_key },
            subject: subject_hash
          }
        end

        private

        def normalize_timestamp(value)
          raise ArgumentError, 'timestamp is required' if value.nil?

          case value
          when Time
            (value.to_f * 1000).to_i
          else
            value.to_i
          end
        end

        def sanitize_attributes(attributes)
          return {} unless attributes.is_a?(Hash)

          attributes.each_with_object({}) do |(key, val), filtered|
            next if val.respond_to?(:to_hash)

            filtered[key] = val
          end
        end

        def subject_hash
          hash = { id: subject_id }
          hash[:type] = subject_type if subject_type
          hash[:attributes] = subject_attributes if subject_attributes.any?
          hash
        end

        def validate_required_fields
          raise ArgumentError, 'allocation_key is required' if allocation_key.nil?
          raise ArgumentError, 'flag_key is required' if flag_key.nil?
          raise ArgumentError, 'variant_key is required' if variant_key.nil?
          raise ArgumentError, 'subject_id is required' if subject_id.nil?
        end
      end
    end
  end
end
