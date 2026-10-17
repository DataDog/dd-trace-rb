# frozen_string_literal: true

module Datadog
  module Core
    module Utils
      # Helper methods for truncating data
      module Truncation
        module_function

        def truncate_in_middle(string, max_prefix_length, max_suffix_length)
          max_length = max_prefix_length + 3 + max_suffix_length
          if string.length > max_length
            "#{string[0...max_prefix_length]}...#{string[-max_suffix_length..-1]}"
          else
            string
          end
        end

        # Truncates +string+ in the middle, keeping at most +max_prefix_bytes+
        # leading and +max_suffix_bytes+ trailing bytes. Partial characters at
        # the cut points are dropped so the result remains valid UTF-8.
        def truncate_in_middle_bytes(string, max_prefix_bytes, max_suffix_bytes)
          max_length = max_prefix_bytes + 3 + max_suffix_bytes
          return string if string.bytesize <= max_length

          prefix = (string.byteslice(0, max_prefix_bytes) || "").scrub("")
          suffix = (string.byteslice(-max_suffix_bytes, max_suffix_bytes) || "").scrub("")

          "#{prefix}...#{suffix}"
        end
      end
    end
  end
end
