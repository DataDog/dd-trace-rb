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
                # DSM is handled at the individual message level in event handlers
                # Call the original method - spans are created by ActiveSupport::Notifications
                super(**kwargs, &block)
              end

              # Monkey patch for each_batch method
              def each_batch(**kwargs, &block)
                # DSM is handled at the individual message level in event handlers
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
