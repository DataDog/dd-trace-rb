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
            # You would think that .compact would work here, but it does not:
            # the result of .map could be an Enumerator::Lazy instance which
            # does not implement #compact.
            array.map(&block).reject do |item|
              item.nil?
            end
          end
        end
      end
    end
  end
end
