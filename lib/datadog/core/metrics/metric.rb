# frozen_string_literal: true

module Datadog
  module Core
    module Metrics
      # A real class (not a Struct constant with a block) so Steep associates
      # the body with the Metric declaration in the signature.
      class Metric < Struct.new(:type, :name, :value, :options)
        def initialize(type, name, value, options = nil)
          super
          self.options = options || {}
        end
      end
    end
  end
end
