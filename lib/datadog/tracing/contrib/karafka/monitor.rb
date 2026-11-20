# frozen_string_literal: true

require_relative "ext"
require_relative "../kafka/ext"
require_relative "kafka_config"

module Datadog
  module Tracing
    module Contrib
      module Karafka
        # Custom monitor for Karafka.
        # Creating a custom monitor, instead of subscribing to an event
        # (e.g. `Karafka.monitor.subscribe 'worker.processed'`),
        # is required because event subscriptions cannot wrap the event execution (`yield`).
        module Monitor
          TRACEABLE_EVENTS = %w[
            worker.processed
          ].freeze

          def instrument(event_id, payload = {}, &block)
            return super unless TRACEABLE_EVENTS.include?(event_id)

            Datadog::Tracing.trace(Ext::SPAN_WORKER_PROCESS) do |span|
              bootstrap_servers = nil
              job = payload[:job]
              job_type = fetch_job_type(job.class)
              consumer = job.executor.topic.consumer

              action = case job_type
              when "Periodic", "PeriodicNonBlocking"
                "tick"
              when "Shutdown"
                "shutdown"
              when "Revoked", "RevokedNonBlocking"
                "revoked"
              when "Idle"
                "idle"
              when "Eofed", "EofedNonBlocking"
                "eofed"
              else
                "consume"
              end

              span.resource = "#{consumer}##{action}"

              if action == "consume"
                span.set_tag(Tracing::Metadata::Ext::TAG_KIND, Tracing::Metadata::Ext::SpanKind::TAG_CONSUMER)
                span.set_tag(Ext::TAG_MESSAGE_COUNT, job.messages.count)
                span.set_tag(Ext::TAG_PARTITION, job.executor.partition)
                span.set_tag(Ext::TAG_OFFSET, job.messages.first.metadata.offset)
                span.set_tag(Ext::TAG_CONSUMER, consumer)
                span.set_tag(Contrib::Ext::Messaging::TAG_DESTINATION, job.executor.topic.name)
                span.set_tag(Contrib::Ext::Messaging::TAG_SYSTEM, Ext::TAG_SYSTEM)

                # Falls back to `Karafka::App.config.kafka` when the topic does not override it.
                topic = job.executor.topic
                bootstrap_servers = KafkaConfig.bootstrap_servers(topic.kafka) if topic.respond_to?(:kafka)
                span.set_tag(Contrib::Kafka::Ext::TAG_KAFKA_BOOTSTRAP_SERVERS, bootstrap_servers) if bootstrap_servers

                # DSM: Track consumer offset stats for batch processing
                if Datadog::DataStreams.enabled?
                  job.messages.each do |message|
                    Datadog::DataStreams.track_kafka_consume(
                      job.executor.topic.name,
                      job.executor.partition,
                      message.metadata.offset,
                    )
                  end
                end
              end

              KafkaConfig.with_job_bootstrap_servers(bootstrap_servers) { super }
            end
          end

          private

          def fetch_job_type(job_class)
            @job_types_cache ||= {}
            @job_types_cache[job_class] ||= job_class.to_s.split("::").last
          end
        end
      end
    end
  end
end
