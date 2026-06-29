# frozen_string_literal: true

require_relative '../ext'

module Datadog
  module Tracing
    module Contrib
      module Racecar
        module Instrumentation
          # Instrumentation that injects Data Streams Monitoring pathway context
          # into the headers of messages produced by Racecar.
          module Producer
            # Injects the DSM pathway context into a message's headers, returning
            # the (possibly newly created) headers hash to pass downstream.
            def self.inject_pathway_context(topic, headers)
              return headers unless Datadog::DataStreams.enabled?

              headers ||= {}
              begin
                Datadog::DataStreams.set_produce_checkpoint(
                  type: Ext::TAG_MESSAGING_SYSTEM,
                  destination: topic,
                  auto_instrumentation: true,
                ) { |key, value| headers[key] = value }
              rescue => e
                Datadog.logger.debug { "Error setting DSM produce checkpoint: #{e.class}: #{e.message}" }
              end

              headers
            end

            # Instrumentation for `Racecar::Consumer#produce`.
            module Consumer
              def self.prepended(base)
                base.prepend(InstanceMethods)
              end

              # Instance methods for consumer-side production instrumentation
              module InstanceMethods
                # `Racecar::Consumer#produce` is protected; preserve that visibility.

                protected

                def produce(payload, topic:, headers: nil, **kwargs)
                  headers = Producer.inject_pathway_context(topic, headers)

                  super
                end
              end
            end

            # Instrumentation for the standalone `Racecar::Producer`.
            module Standalone
              def self.prepended(base)
                base.prepend(InstanceMethods)
              end

              # Instance methods for standalone producer instrumentation
              module InstanceMethods
                def produce_async(value:, topic:, **options)
                  options[:headers] = Producer.inject_pathway_context(topic, options[:headers])

                  super
                end

                def produce_sync(value:, topic:, **options)
                  options[:headers] = Producer.inject_pathway_context(topic, options[:headers])

                  super
                end
              end
            end
          end
        end
      end
    end
  end
end
