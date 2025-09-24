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
            puts "🔍 [WATERDROP PATCHER] patch() called"
            puts "🔍 [WATERDROP PATCHER] defined?(::WaterDrop::Producer) = #{defined?(::WaterDrop::Producer)}"
            
            # Patch WaterDrop::Producer to add our middleware and event subscription
            if defined?(::WaterDrop::Producer)
              puts "🔍 [WATERDROP PATCHER] WaterDrop::Producer is defined, patching..."
              patch_producer
            else
              puts "🔍 [WATERDROP PATCHER] WaterDrop::Producer is NOT defined, skipping patch"
            end
          end

          def patch_producer
            puts "🔍 [WATERDROP PATCHER] patch_producer() called"
            require_relative 'instrumentation/producer'
            ::WaterDrop::Producer.prepend(Instrumentation::Producer)
            puts "🔍 [WATERDROP PATCHER] WaterDrop::Producer patched successfully"
          end
        end
      end
    end
  end
end
