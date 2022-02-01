# typed: true
require 'datadog/tracing/contrib/patcher'
require 'datadog/tracing/contrib/kafka/ext'
require 'datadog/tracing/contrib/kafka/events'
require 'datadog/tracing/contrib/kafka/integration'

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
