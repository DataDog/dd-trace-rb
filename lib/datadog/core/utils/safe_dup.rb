require_relative '../backport'

module Datadog
  module Core
    module Utils
      # Helper methods for safer dup
      module SafeDup
        # String#+@ was introduced in Ruby 2.3
        if String.method_defined?(:+@) && String.method_defined?(:-@)
          def self.frozen_or_dup(v)
            # For the case of a String we use the methods +@ and -@.
            # Those methods are only for String objects
            # they are faster and chepaer on the memory side.
            # Check the benchmark on
            # https://github.com/DataDog/dd-trace-rb/pull/2704
            if v.is_a?(String)
              # If the string is not frozen, the +(-v) will:
              # - first create a frozen deduplicated copy with -v
              # - then it will dup it more efficiently with +v
              v.frozen? ? v : +(-v)
            else
              v.frozen? ? v : Core::BackportFrom24.dup(v)
            end
          end

          def self.frozen_dup(v)
            # For the case of a String we use the methods -@
            # That method are only for String objects
            # they are faster and chepaer on the memory side.
            # Check the benchmark on
            # https://github.com/DataDog/dd-trace-rb/pull/2704
            if v.is_a?(String)
              -v if v
            else
              v.frozen? ? v : Core::BackportFrom24.dup(v).freeze
            end
          end
        else
          def self.frozen_or_dup(v)
            v.frozen? ? v : Core::BackportFrom24.dup(v)
          end

          def self.frozen_dup(v)
            v.frozen? ? v : Core::BackportFrom24.dup(v).freeze
          end
        end
      end
    end
  end
end
