# frozen_string_literal: true

require_relative '../../../data_streams/pathway_codec'

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
                # Only run data streams code if enabled
                if Datadog.configuration.tracing.data_streams.enabled
                  puts 'deliver_messages (DSM enabled)'

                  processor = Datadog.configuration.tracing.data_streams.processor

                  messages.each do |message|
                    message[:headers] ||= {}
                    processor.set_produce_checkpoint('kafka', message[:topic]) do |key, value|
                      message[:headers][key] = value
                    end
                  end
                else
                  puts 'deliver_messages (DSM disabled)'
                end

                # Call the original method - spans are created by ActiveSupport::Notifications
                super(messages, **kwargs)
              end

              # Monkey patch for send_messages method (async producer)
              def send_messages(messages, **kwargs)
                # Only run DSM code if enabled
                if Datadog.configuration.tracing.data_streams.enabled
                  puts 'send_messages (DSM enabled)'

                  processor = Datadog.configuration.tracing.data_streams.processor

                  # Create checkpoint for async producer (direction:out)
                  messages.each do |message|
                    message[:headers] ||= {}
                    processor.set_produce_checkpoint('kafka', message[:topic]) { |key, value| message[:headers][key] = value }
                  end
                else
                  puts 'send_messages (DSM disabled)'
                end

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
