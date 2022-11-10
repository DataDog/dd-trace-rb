# frozen_string_literal: true
# typed: false

module Datadog
  module Core
    module Utils
      # A collection of refinements for core Ruby features.
      # Backports future features to old rubies.
      module Refinement
        # rubocop:disable Style/Documentation
        module Regexp
          refine ::Regexp do
            # `Regexp::match?` is measurably the most performant
            # way to check if a String matches a regular expression.
            #
            # Introduced in Ruby 2.4.
            def match?(*args)
              !match(*args).nil?
            end
          end
        end

        module String
          refine ::String do
            # When not sure if a String is mutable and but it's necessary to perform
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
