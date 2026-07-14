# frozen_string_literal: true

require_relative '../../../data_streams'
require_relative 'ext'

module Datadog
  module Tracing
    module Contrib
      module ActiveJob
        # Propagates Data Streams Monitoring pathway context through the serialized
        # job payload, allowing produce (enqueue) and consume (perform) checkpoints
        # to be connected across the process boundary.
        #
        # The DSM calls are rescued in isolation so a checkpoint failure can never
        # break a job, while a genuine error raised by the underlying serialization
        # still propagates.
        #
        # Only prepended on ActiveJob 5.0+, where `serialize`/`deserialize` are instance
        # methods the framework routes through. ActiveJob 4.2 deserializes via a class
        # method, so the pathway cannot be propagated there.
        module DataStreams
          def serialize
            job_data = super
            return job_data unless Datadog::DataStreams.enabled?

            begin
              Datadog::DataStreams.set_produce_checkpoint(
                type: Ext::TAG_COMPONENT,
                destination: queue_name,
                auto_instrumentation: true
              ) do |key, value|
                job_data[key] = value
              end
            rescue => e
              Datadog.logger.debug { "Error setting DSM produce checkpoint: #{e.class}: #{e.message}" }
            end

            job_data
          end

          def deserialize(job_data)
            super

            return unless Datadog::DataStreams.enabled?

            begin
              Datadog::DataStreams.set_consume_checkpoint(
                type: Ext::TAG_COMPONENT,
                source: queue_name,
                auto_instrumentation: true
              ) do |key|
                job_data[key]
              end
            rescue => e
              Datadog.logger.debug { "Error setting DSM consume checkpoint: #{e.class}: #{e.message}" }
            end
          end
        end
      end
    end
  end
end
