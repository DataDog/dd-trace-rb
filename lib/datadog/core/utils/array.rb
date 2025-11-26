# frozen_string_literal: true

module Datadog
  module Core
    module Utils
      # Common array-related utility functions.
      module Array
        def self.filter_map(array, &block)
          if array.respond_to?(:filter_map)
            # DEV Supported since Ruby 2.7, saves an intermediate object creation
            array.filter_map(&block)
          else
            array.map(&block).compact
          end
        end
      end
    end
  end
end
