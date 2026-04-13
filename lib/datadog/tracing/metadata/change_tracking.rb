# frozen_string_literal: true

require_relative 'tagging'

module Datadog
  module Tracing
    module Metadata
      # Adds metadata change tracking on top of {Tagging}.
      module ChangeTracking
        include Tagging

        def set_tag(key, value = nil)
          previous_value = get_tag(key)

          super

          return if metric_tag?(key, value)
          return if metadata_change_ignored?(key)

          publish_metadata_change(previous_value, key)
        end

        def clear_tag(key)
          previous_value = get_tag(key)

          super

          return if metadata_change_ignored?(key)

          publish_metadata_change(previous_value, key)
        end

        def set_metric(key, value)
          previous_value = get_tag(key)

          super

          return if metadata_change_ignored?(key)

          publish_metadata_change(previous_value, key)
        end

        def clear_metric(key)
          previous_value = get_tag(key)

          super

          return if metadata_change_ignored?(key)

          publish_metadata_change(previous_value, key)
        end

        private

        def metric_tag?(key, value)
          return false if Metadata::Tagging::ENSURE_AGENT_TAGS[key]
          return false unless value.is_a?(Numeric)

          !(value.is_a?(Integer) && !Metadata::Tagging::NUMERIC_TAG_SIZE_RANGE.cover?(value))
        end

        def metadata_change_ignored?(_key)
          false
        end
      end
    end
  end
end
