# frozen_string_literal: true

require_relative '../patcher'
require_relative 'ext'
require_relative 'events'

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

            # Apply monkey patches for additional instrumentation (e.g., DSM)
            patch_consumer
            patch_producer
          end

          def patch_consumer
            require_relative 'instrumentation/consumer'

            ::Racecar::Runner.prepend(Instrumentation::Consumer) if defined?(::Racecar::Runner)
          end

          def patch_producer
            require_relative 'instrumentation/producer'

            ::Racecar::Consumer.prepend(Instrumentation::Producer::Consumer) if defined?(::Racecar::Consumer)
            ::Racecar::Producer.prepend(Instrumentation::Producer::Standalone) if defined?(::Racecar::Producer)
          end
        end
      end
    end
  end
end
