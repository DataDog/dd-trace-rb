# frozen_string_literal: true

require_relative 'ext'

module Datadog
  module Tracing
    module Contrib
      module Karafka
        # Custom monitor for Karafka
        class Monitor < ::Karafka::Instrumentation::Monitor
          TRACEABLE_EVENTS = %w[
            worker.processed
          ].freeze

          def instrument(event_id, payload = EMPTY_HASH, &block)
            return super unless TRACEABLE_EVENTS.include?(event_id)

            Datadog::Tracing.trace(Ext::SPAN_WORKER_PROCESS) do |span|
              job = payload[:job]
              job_type = fetch_job_type(job.class)
              consumer = job.executor.topic.consumer

              action = case job_type
                when 'Periodic'
                  'tick'
                when 'PeriodicNonBlocking'
                  'tick'
                when 'Shutdown'
                  'shutdown'
                when 'Revoked'
                  'revoked'
                when 'RevokedNonBlocking'
                  'revoked'
                when 'Idle'
                  'idle'
                when 'Eofed'
                  'eofed'
                when 'EofedNonBlocking'
                  'eofed'
                else
                  'consume'
                end

              span.resource = "#{consumer}##{action}"

              if action == 'consume'
                span.set_tag(Ext::TAG_MESSAGE_COUNT, job.messages.count)
                span.set_tag(Ext::TAG_PARTITION, job.executor.partition)
                span.set_tag(Ext::TAG_OFFSET, job.messages.first.metadata.offset)
                span.set_tag(Ext::TAG_TOPIC, job.executor.topic.name)
                span.set_tag(Ext::TAG_CONSUMER, consumer)
              end

              super
            end
          end

          private

          def fetch_job_type(job_class)
            @job_types_cache ||= {}
            @job_types_cache[job_class] ||= job_class.to_s.split('::').last
          end
        end
      end
    end
  end
end
