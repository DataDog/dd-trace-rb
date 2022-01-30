# typed: true
require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/kafka/ext'
require 'ddtrace/contrib/kafka/events'
require 'ddtrace/contrib/kafka/integration'

module Datadog
  module Tracing
    module Contrib
      module Kafka
        # Patcher enables patching of 'kafka' module.
        module Patcher
          include Contrib::Patcher

          module_function

          def target_version
            Integration.version
          end

          def patch
            # Subscribe to Kafka events
            Events.subscribe!
          end
        end
      end
    end
  end
end
