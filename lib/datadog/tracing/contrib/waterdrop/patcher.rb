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
            require_relative 'monitor'

            ::WaterDrop::Instrumentation::Monitor.prepend(Monitor)
          end
        end
      end
    end
  end
end
