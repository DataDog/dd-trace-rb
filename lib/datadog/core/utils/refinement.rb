# frozen_string_literal: true
# typed: true

module Datadog
  module Core
    module Utils
      # A collection of refinements for core Ruby features.
      # Backports future features to old rubies.
      module Refinement
        # rubocop:disable Style/Documentation
        module String
          refine ::String do
            # Returns self if self is not frozen.
            # Otherwise, returns self.dup, which is not frozen.
            #
            # Rationale: when we are not sure if a String is mutable and want to perform
            # changes to it, `+@` is measurable faster than a possibly unnecessary `.dup`.
            #
            # Introduced in Ruby 2.3.
            def +@
              frozen? ? dup : self
            end
          end
        end
        # rubocop:enable Style/Documentation
      end
    end
  end
end
