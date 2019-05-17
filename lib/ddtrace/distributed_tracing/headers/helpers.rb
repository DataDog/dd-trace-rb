require 'ddtrace/configuration'
require 'ddtrace/span'
require 'ddtrace/ext/priority'

module Datadog
  module DistributedTracing
    module Headers
      # Helpers module provides common helper functions for distributed tracing headers
      module Helpers
        # Base provides common methods for distributed header helper classes
        def self.clamp_sampling_priority(sampling_priority)
          # B3 doesn't have our -1 (USER_REJECT) and 2 (USER_KEEP) priorities so convert to acceptable 0/1
          if sampling_priority < 0
            sampling_priority = Ext::Priority::AUTO_REJECT
          elsif sampling_priority > 1
            sampling_priority = Ext::Priority::AUTO_KEEP
          end

          sampling_priority
        end

        def self.truncate_base16_number(value)
          # Lowercase if we want to parse base16 e.g. 3E8 => 3e8
          # DEV: Ruby will parse `3E8` just fine, but to test
          #      `num.to_s(base) == value` we need to lowercase
          value = value.downcase

          # Truncate to trailing 16 characters if length is greater than 16
          # https://github.com/apache/incubator-zipkin/blob/21fe362899fef5c593370466bc5707d3837070c2/zipkin/src/main/java/zipkin2/storage/StorageComponent.java#L49-L53
          # DEV: This ensures we truncate B3 128-bit trace and span ids to 64-bit
          value = value[value.length - 16, 16] if value.length > 16

          # Remove any leading zeros
          # DEV: When we call `num.to_s(16)` later Ruby will not add leading zeros
          #      for us so we want to make sure the comparision will work as expected
          # DEV: regex, remove all leading zeros up until we find the last 0 in the string
          #      or we find the first non-zero, this allows `'0000' -> '0'` and `'00001' -> '1'`
          value = value.sub(/^0*(?=(0$)|[^0])/, '')

          value
        end
      end
    end
  end
end
