# frozen_string_literal: true

module Datadog
  module Core
    module Metrics
      Metric = Struct.new(:type, :name, :value, :options) do
        # steep:ignore:start
        def initialize(*args)
          super
          self.options = options || {}
        end
        # steep:ignore:end
      end
    end
  end
end
