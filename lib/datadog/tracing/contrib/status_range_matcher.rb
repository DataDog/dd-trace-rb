# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      # Useful checking whether the defined range covers status code
      class StatusRangeMatcher
        attr_reader :ranges

        def initialize(ranges)
          @ranges = Array(ranges)
        end

        def +(other)
          StatusRangeMatcher.new(@ranges + other.ranges)
        end
        alias_method :concat, :+

        def include?(status)
          @ranges.any? do |e|
            case e
            when Range
              e.include? status
            when Integer
              e == status
            end
          end
        end
      end
    end
  end
end
