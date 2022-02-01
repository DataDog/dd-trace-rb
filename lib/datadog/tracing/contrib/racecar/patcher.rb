# typed: true
require 'datadog/tracing/contrib/patcher'
require 'datadog/tracing/contrib/racecar/ext'
require 'datadog/tracing/contrib/racecar/events'
require 'datadog/tracing/contrib/racecar/integration'

module Datadog
  module Tracing
    module Contrib
      module Racecar
        # Patcher enables patching of 'racecar' module.
        module Patcher
          include Contrib::Patcher

          module_function

          def target_version
            Integration.version
          end

          def patch
            # Subscribe to Racecar events
            Events.subscribe!
          end
        end
      end
    end
  end
end
