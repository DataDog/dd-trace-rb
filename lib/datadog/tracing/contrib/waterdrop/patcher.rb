# frozen_string_literal: true

require_relative '../patcher'
require_relative 'ext'
require_relative 'middleware'
require_relative 'events'

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
            # Patch WaterDrop::Producer to add our middleware and event subscription
            patch_producer if defined?(::WaterDrop::Producer)
          end

          def patch_producer
            require_relative 'instrumentation/producer'
            ::WaterDrop::Producer.prepend(Instrumentation::Producer)
          end
        end
      end
    end
  end
end
