# frozen_string_literal: true

module Datadog
  module Core
    module Metrics
      Metric = Struct.new(:type, :name, :value, :options)

      class Metric
        def initialize(type, name, value, options = nil)
          super(type, name, value, options || {}) # steep:ignore UnexpectedPositionalArgument
        end
      end
    end
  end
end
