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

          # Ensures #initialize can call true.dup safely
          module RefineTrue
            refine TrueClass do
              def dup
                self
              end
            end
          end

          # Ensures #initialize can call false.dup safely
          module RefineFalse
            refine FalseClass do
              def dup
                self
              end
            end
          end

          # Ensures #initialize can call 1.dup safely
          module RefineInteger
            refine Integer do
              def dup
                self
              end
            end
          end

          # Ensures #initialize can call 1.0.dup safely
          module RefineFloat
            refine Float do
              def dup
                self
              end
            end
          end

          using RefineNil
          using RefineTrue
          using RefineFalse
          using RefineInteger
          using RefineFloat
        end

        # String#+@ was introduced in Ruby 2.3
        if String.method_defined?(:+@) && String.method_defined?(:-@)
          def self.frozen_or_dup(v)
            case v
            when String
              # If the string is not frozen, the +(-v) will:
              # - first create a frozen deduplicated copy with -v
              # - then it will dup it more efficiently with +v
              v.frozen? ? v : +(-v)
            else
              v.frozen? ? v : v.dup
            end
          end

          def self.frozen_dup(v)
            case v
            when String
              -v if v
            else
              v.frozen? ? v : v.dup.freeze
            end
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
