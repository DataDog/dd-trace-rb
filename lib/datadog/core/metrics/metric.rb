module Datadog
  module Core
    module Metrics
      Metric = Struct.new(:type, :name, :value, :options) do
        def initialize(*args)
          super
          self.options = options || {}
        end
      end
    end
  end
end
