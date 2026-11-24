# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module Kafka
        module Instrumentation
          # Instrumentation for Kafka::Consumer
          module Consumer
            def self.prepended(base)
              base.prepend(InstanceMethods)
            end

            # Instance methods for consumer instrumentation
            module InstanceMethods
              # Checked per message, not at entry: Remote Config can enable DSM while the loop runs.
              def each_message(**kwargs, &block)
                wrapped_block = proc do |message|
                  if Datadog::DataStreams.enabled?
                    Datadog.logger.debug { "Kafka each_message: DSM enabled for topic #{message.topic}" }

                    begin
                      headers = message.headers || {}
                      Datadog::DataStreams.set_consume_checkpoint(
                        type: "kafka",
                        source: message.topic,
                        auto_instrumentation: true,
                      ) { |key| headers[key] }
                    rescue => e
                      Datadog.logger.debug("Error setting DSM checkpoint: #{e.class}: #{e.message}")
                    end
                  end

                  yield(message) if block
                end

                super(**kwargs, &wrapped_block)
              end

              def each_batch(**kwargs, &block)
                wrapped_block = proc do |batch|
                  if Datadog::DataStreams.enabled?
                    Datadog.logger.debug { "Kafka each_batch: DSM enabled for topic #{batch.topic}" }

                    begin
                      Datadog::DataStreams.set_consume_checkpoint(
                        type: "kafka",
                        source: batch.topic,
                        auto_instrumentation: true,
                      )
                    rescue => e
                      Datadog.logger.debug("Error setting DSM checkpoint: #{e.class}: #{e.message}")
                    end
                  end

                  yield(batch) if block
                end

                super(**kwargs, &wrapped_block)
              end
            end
          end
        end
      end
    end
  end
end
