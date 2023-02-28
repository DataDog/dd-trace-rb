# frozen_string_literal: true

require_relative 'helpers'

module Datadog
  module Tracing
    module Distributed
      # Common fetcher that retrieves fields from a Hash data input
      class Fetcher
        # @param data [Hash]
        def initialize(data)
          @data = data
        end

        def [](key)
          @data[key]
        end

        def id(key, base: 10)
          Helpers.value_to_id(self[key], base: base)
        end

        def number(key, base: 10)
          Helpers.value_to_number(self[key], base: base)
        end
      end
    end
  end
end
