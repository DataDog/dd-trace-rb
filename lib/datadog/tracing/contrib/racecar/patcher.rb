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
            if defined?(::Racecar::Runner) && ::Racecar::Runner.private_method_defined?(:process)
              # Racecar 2.x (rdkafka): the runner dispatches each message through
              # `Runner#process`/`#process_batch`, where the rdkafka messages and
              # their headers are available for per-message DSM checkpoints.
              require_relative 'instrumentation/consumer'
              ::Racecar::Runner.prepend(Instrumentation::Consumer)
            elsif defined?(::Kafka::Consumer)
              # Racecar 1.x (ruby-kafka): the runner consumes directly through
              # `Kafka::Consumer#each_message`/`#each_batch`, so reuse the kafka
              # integration's consumer instrumentation.
              require_relative '../kafka/instrumentation/consumer'
              ::Kafka::Consumer.prepend(Contrib::Kafka::Instrumentation::Consumer)
            end
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
