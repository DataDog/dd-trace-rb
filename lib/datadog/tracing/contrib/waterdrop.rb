# frozen_string_literal: true

require_relative 'component'
require_relative 'waterdrop/integration'

module Datadog
  module Tracing
    module Contrib
      # `WaterDrop` integration public API
      module WaterDrop
        def self.inject(digest, data)
          raise 'Please invoke Datadog.configure at least once before calling this method' unless @propagation

          @propagation.inject!(digest, data)
        end

        def self.extract(data)
          raise 'Please invoke Datadog.configure at least once before calling this method' unless @propagation

          @propagation.extract(data)
        end

        Contrib::Component.register('waterdrop') do |config|
          tracing = config.tracing
          tracing.propagation_style

          # For WaterDrop, we use the standard propagation since it's Kafka-based
          @propagation = Contrib::Propagation::Kafka.new(
            propagation_style_inject: tracing.propagation_style_inject,
            propagation_style_extract: tracing.propagation_style_extract,
            propagation_extract_first: tracing.propagation_extract_first
          )
        end
      end
    end
  end
end
