# frozen_string_literal: true

require_relative '../sampling/ext'
require_relative '../utils'

module Datadog
  module Tracing
    module Distributed
      # Helpers module provides common helper functions for distributed tracing data
      module Helpers
        # Base provides common methods for distributed helper classes
        def self.clamp_sampling_priority(sampling_priority)
          # B3 doesn't have our -1 (USER_REJECT) and 2 (USER_KEEP) priorities so convert to acceptable 0/1
          if sampling_priority < 0
            sampling_priority = Sampling::Ext::Priority::AUTO_REJECT
          elsif sampling_priority > 1
            sampling_priority = Sampling::Ext::Priority::AUTO_KEEP
          end

          sampling_priority
        end

        def self.parse_decimal_id(value)
          return unless value

          value = value.to_s
          num   = value.to_i

          return unless num.to_s(10) == value

          num
        end

        def self.parse_hex_id(value, length: nil)
          return unless value

          value = value.to_s.downcase
          value = value[value.length - length, length] if length && value.length > length
          value = value.sub(/^0*(?=(0$)|[^0])/, '')

          num = value.to_i(16)

          return unless num.to_s(16) == value

          num
        end
      end
    end
  end
end
