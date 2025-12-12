# frozen_string_literal: true

require_relative 'component'
require_relative 'waterdrop/integration'
require_relative 'waterdrop/distributed/propagation'

module Datadog
  module Tracing
    module Contrib
      # `WaterDrop` integration public API
      module WaterDrop
        def self.inject(digest, data)
          raise 'Please invoke Datadog.configure at least once before calling this method' unless @propagation

          # Steep: https://github.com/soutaro/steep/issues/477
          @propagation.inject!(digest, data) # steep:ignore NoMethod
        end

        def self.extract(data)
          raise 'Please invoke Datadog.configure at least once before calling this method' unless @propagation

          # Steep: https://github.com/soutaro/steep/issues/477
          @propagation.extract(data) # steep:ignore NoMethod
        end

        Contrib::Component.register('waterdrop') do |config|
          tracing = config.tracing
          tracing.propagation_style

          @propagation = WaterDrop::Distributed::Propagation.new(
            propagation_style_inject: tracing.propagation_style_inject,
            propagation_style_extract: tracing.propagation_style_extract,
            propagation_extract_first: tracing.propagation_extract_first
          )
        end
      end
    end
  end
end
