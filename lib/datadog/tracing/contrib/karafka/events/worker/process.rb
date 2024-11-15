# frozen_string_literal: true

require_relative '../../ext'
require_relative '../../event'

module Datadog
  module Tracing
    module Contrib
      module Karafka
        module Events
          module Worker
            module Process
              include Karafka::Event

              def self.subscribe!
                ::Karafka.monitor.subscribe 'worker.process' do |event|
                  # Start a trace
                  span = Tracing.trace(Ext::SPAN_WORKER_PROCESS, **span_options)

                  job = event[:job]
                  job_type = fetch_job_type(job.class)
                  consumer = job.executor.topic.consumer
                  topic = job.executor.topic.name

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
                  span.set_tag(Ext::TAG_TOPIC, topic) if topic

                  if action == 'consume'
                    span.set_tag(Ext::TAG_MESSAGE_COUNT, job.messages.count)
                    span.set_tag(Ext::TAG_PARTITION, job.executor.partition)
                    span.set_tag(Ext::TAG_OFFSET, job.messages.first.metadata.offset)
                  end

                  span
                end

                ::Karafka.monitor.subscribe 'worker.completed' do |event|
                  Tracing.active_span&.finish
                end
              end

              def self.span_options
                super.merge({ tags: { Tracing::Metadata::Ext::TAG_OPERATION => Ext::TAG_OPERATION_PROCESS_BATCH } })
              end

              def self.fetch_job_type(job_class)
                @job_types_cache ||= {}
                @job_types_cache[job_class] ||= job_class.to_s.split('::').last
              end
            end
          end
        end
      end
    end
  end
end
