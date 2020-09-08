require 'ddtrace/contrib/patcher'
require 'ddtrace/ext/app_types'
require 'ddtrace/contrib/kafka/ext'
require 'ddtrace/contrib/kafka/events'

module Datadog
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
