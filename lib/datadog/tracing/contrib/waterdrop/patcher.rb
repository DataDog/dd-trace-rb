# frozen_string_literal: true

require_relative '../patcher'
require_relative 'ext'
require_relative 'distributed/propagation'

module Datadog
  module Tracing
    module Contrib
      module WaterDrop
        # Patcher enables patching of 'waterdrop' module.
        module Patcher
          include Contrib::Patcher

          module_function

          def target_version
            Integration.version
          end

          def patch
            require_relative 'producer'
            require_relative 'middleware'

            ::WaterDrop::Producer.prepend(Producer)
            ::WaterDrop.instrumentation.subscribe('producer.configured') do |event|
              producer = event[:producer]

              included_middlewares = producer.middleware.instance_variable_get(:@steps)
              producer.middleware.append(Middleware) unless included_middlewares.include?(Middleware)
            end
          end
        end
      end
    end
  end
end
