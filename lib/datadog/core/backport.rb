# frozen_string_literal: true

module Datadog
  module Core
    # This module is used to provide features from Ruby 2.5+ to older Rubies
    module BackportFrom25
      module_function

      if ::String.method_defined?(:delete_prefix)
        def string_delete_prefix(string, prefix)
          string.delete_prefix(prefix)
        end
      else
        def string_delete_prefix(string, prefix)
          prefix = prefix.to_s
          if string.start_with?(prefix)
            string[prefix.length..-1] || raise('rbs-guard: String#[] is non-nil as `prefix` is guaranteed present')
          else
            string.dup
          end
        end
      end
    end
  end
end
