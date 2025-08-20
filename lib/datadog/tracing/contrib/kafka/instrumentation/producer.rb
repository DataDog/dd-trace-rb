# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module Kafka
        module Instrumentation
          # Instrumentation for Kafka::Producer
          module Producer
            def self.included(base)
              base.prepend(InstanceMethods)
            end

            # Instance methods for producer instrumentation
            module InstanceMethods
              # Monkey patch for deliver_messages method
              # This is where you will add DSM instrumentation
              def deliver_messages(messages = nil, **kwargs)
                puts "deliver_messages"

                # TODO: Add DSM instrumentation here
                # This is where you would:
                # 1. Extract pathway hash from message headers
                # 2. Set checkpoint information
                # 3. Add DSM-specific tags and metrics

                # Call the original method - spans are created by ActiveSupport::Notifications
                super(messages, **kwargs)
              end

              # Monkey patch for send_messages method (async producer)
              def send_messages(messages, **kwargs)
                puts "send_messages"

                # TODO: Add DSM instrumentation for async sends

                # Call the original method - spans are created by ActiveSupport::Notifications
                super(messages, **kwargs)
              end
            end
          end
        end
      end
    end
  end
end
