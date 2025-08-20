# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module Kafka
        module Instrumentation
          # Instrumentation for Kafka::Consumer
          module Consumer
            def self.included(base)
              base.prepend(InstanceMethods)
            end

            # Instance methods for consumer instrumentation
            module InstanceMethods
              # Monkey patch for each_message method
              def each_message(**kwargs, &block)
                puts "each_message"

                # TODO: Add DSM instrumentation for message consumption
                # This is where you would:
                # 1. Extract pathway hash from message headers
                # 2. Set checkpoint information for consumed messages
                # 3. Add DSM-specific tags for data lineage

                # Call the original method - spans are created by ActiveSupport::Notifications
                super(**kwargs, &block)
              end

              # Monkey patch for each_batch method
              def each_batch(**kwargs, &block)
                puts "each_batch"

                # TODO: Process DSM pathway information for the entire batch

                # Call the original method - spans are created by ActiveSupport::Notifications
                super(**kwargs, &block)
              end
            end
          end
        end
      end
    end
  end
end
