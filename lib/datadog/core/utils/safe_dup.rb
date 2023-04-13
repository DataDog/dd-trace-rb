module Datadog
  module Core
    module Utils
      # Helper methods for safer dup
      module SafeDup
        if RUBY_VERSION < '2.2' # nil.dup only fails in Ruby 2.1
          # Ensures #initialize can call nil.dup safely
          module RefineNil
            refine NilClass do
              def dup
                self
              end
            end
          end

          using RefineNil
        end

        # String#+@ was introduced in Ruby 2.3
        if String.method_defined?(:+@) && String.method_defined?(:-@)
          def self.frozen_or_dup(v)
            # If the string is not frozen, the +(-v) will:
            # - first create a frozen deduplicated copy with -v
            # - then it will dup it more efficiently with +v
            v.frozen? ? v : +(-v)
          end

          def self.frozen_dup(v)
            -v if v
          end
        else
          def self.frozen_or_dup(v)
            v.frozen? ? v : v.dup
          end

          def self.frozen_dup(v)
            v.frozen? ? v : v.dup.freeze
          end
        end
      end
    end
  end
end
