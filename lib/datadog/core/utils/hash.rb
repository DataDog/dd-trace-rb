# frozen_string_literal: true

module Datadog
  module Core
    module Utils
      # Refinements for {Hash}.
      module Hash
        # This refinement ensures modern rubies are allowed to use newer,
        # simpler, and more performant APIs.
        module Refinement
          # Introduced in Ruby 2.4
          unless ::Hash.method_defined?(:compact)
            refine ::Hash do
              def compact
                reject { |_k, v| v.nil? }
              end
            end
          end

          # Introduced in Ruby 2.4
          unless ::Hash.method_defined?(:compact!)
            refine ::Hash do
              def compact!
                reject! { |_k, v| v.nil? }
              end
            end
          end
        end
      end
    end
  end
end
