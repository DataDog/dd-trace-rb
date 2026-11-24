# frozen_string_literal: true

require_relative "../../../data_streams"
require_relative "ext"

module Datadog
  module Tracing
    module Contrib
      module Sidekiq
        module DataStreams
          RUNNING_JID_KEY = :datadog_sidekiq_data_streams_running_jid

          def self.produce(job)
            return unless Datadog::DataStreams.enabled?
            return if active_job_handles?(job)
            return if repush?(job)

            Datadog::DataStreams.set_produce_checkpoint(
              type: Ext::TAG_COMPONENT,
              destination: job["queue"],
              auto_instrumentation: true,
            ) do |key, value|
              job[key] = value
            end
          rescue => e
            Datadog.logger.debug { "Error setting Sidekiq DSM produce checkpoint: #{e.class}: #{e.message}" }
          end

          def self.consume(job, queue)
            return yield unless Datadog::DataStreams.enabled?
            return yield if active_job_handles?(job)

            saved = save_state(job)
            begin
              Datadog::DataStreams.set_consume_checkpoint(
                type: Ext::TAG_COMPONENT,
                source: queue,
                auto_instrumentation: true,
              ) do |key|
                job[key]
              end
            rescue => e
              Datadog.logger.debug { "Error setting Sidekiq DSM consume checkpoint: #{e.class}: #{e.message}" }
            end

            begin
              yield
            ensure
              restore_state(saved)
            end
          end

          def self.repush?(job)
            return false unless job.key?(Datadog::DataStreams::Processor::PROPAGATION_KEY)

            Datadog::DataStreams.pathway_context.nil? || job["jid"] == Thread.current[RUNNING_JID_KEY]
          end

          def self.active_job_handles?(job)
            return false unless job["wrapped"]
            return false unless defined?(::ActiveJob::Base) && defined?(Contrib::ActiveJob::DataStreams)

            (::ActiveJob::Base <= Contrib::ActiveJob::DataStreams) == true
          end

          def self.save_state(job)
            context = Datadog::DataStreams.pathway_context
            processor = Datadog::DataStreams.send(:processor)
            jid = Thread.current[RUNNING_JID_KEY]
            Thread.current[RUNNING_JID_KEY] = job["jid"]
            Datadog::DataStreams.pathway_context = nil
            {context: context, processor: processor, jid: jid}
          rescue => e
            Datadog.logger.debug { "Error saving Sidekiq DSM pathway context: #{e.class}: #{e.message}" }
            nil
          end

          def self.restore_state(saved)
            return unless saved

            Thread.current[RUNNING_JID_KEY] = saved[:jid]
            return unless Datadog::DataStreams.send(:processor).equal?(saved[:processor])

            Datadog::DataStreams.pathway_context = saved[:context]
          rescue => e
            Datadog.logger.debug { "Error restoring Sidekiq DSM pathway context: #{e.class}: #{e.message}" }
          end
        end
      end
    end
  end
end
