# frozen_string_literal: true

module Datadog
  module Core
    module Metrics
      class Metric < Struct.new(:type, :name, :value, :options)
        def initialize(type, name, value, options = nil)
          super
          self.options = options || {}
        end
      end
    end
  end
end
