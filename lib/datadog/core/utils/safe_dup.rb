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

        def self.frozen_or_dup(v)
          v.frozen? ? v : v.dup
        end
      end
    end
  end
end
