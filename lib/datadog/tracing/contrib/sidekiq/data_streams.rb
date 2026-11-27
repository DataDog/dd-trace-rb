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

            context = Datadog::DataStreams.pathway_context
            processor = Datadog::DataStreams.send(:processor)
            begin
              Datadog::DataStreams.set_produce_checkpoint(
                type: Ext::TAG_COMPONENT,
                destination: job["queue"],
                auto_instrumentation: true,
              ) do |key, value|
                job[key] = value
              end
            ensure
              Datadog::DataStreams.pathway_context = context if Datadog::DataStreams.send(:processor).equal?(processor)
            end
          rescue => e
            Datadog.logger.debug { "Error setting Sidekiq DSM produce checkpoint: #{e.class}: #{e.message}" }
          end

          def self.consume(job, queue)
            return yield unless Datadog::DataStreams.enabled?

            if active_job_handles?(job)
              hand_over_to_active_job(job)
              return yield
            end

            saved = save_state(job)
            begin
              Datadog::DataStreams.set_consume_checkpoint(
                type: Ext::TAG_COMPONENT,
                source: queue,
                auto_instrumentation: true,
              ) do |key|
                job[key] || wrapped_payload(job)&.[](key)
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
            key = Datadog::DataStreams::Processor::PROPAGATION_KEY
            return false unless job.key?(key) || wrapped_payload(job)&.key?(key)

            running_jid = Thread.current[RUNNING_JID_KEY]
            running_jid.nil? || running_jid == job["jid"]
          end

          def self.hand_over_to_active_job(job)
            key = Datadog::DataStreams::Processor::PROPAGATION_KEY
            context = job[key]
            payload = wrapped_payload(job)
            payload[key] = context if context && payload && !payload.key?(key)
          rescue => e
            Datadog.logger.debug { "Error handing Sidekiq DSM pathway context to ActiveJob: #{e.class}: #{e.message}" }
          end

          def self.wrapped_payload(job)
            return unless job["wrapped"]

            payload = job["args"]&.first
            payload if payload.is_a?(Hash)
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
