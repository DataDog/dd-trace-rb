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
                # Only run data streams code if enabled
                if Datadog.configuration.tracing.data_streams.enabled
                  puts 'each_message (DSM enabled)'

                  processor = Datadog.configuration.tracing.data_streams.processor
                  processor.set_checkpoint(['direction:in', 'type:kafka'], Time.now.to_f)
                else
                  puts 'each_message (DSM disabled)'
                end

                # Call the original method - spans are created by ActiveSupport::Notifications
                super(**kwargs, &block)
              end

              # Monkey patch for each_batch method
              def each_batch(**kwargs, &block)
                # Only run DSM code if enabled
                if Datadog.configuration.tracing.data_streams.enabled
                  puts 'each_batch (DSM enabled)'

                  # TODO: Process DSM pathway information for the entire batch
                else
                  puts 'each_batch (DSM disabled)'
                end

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
