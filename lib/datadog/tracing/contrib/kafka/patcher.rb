# frozen_string_literal: true

require_relative '../patcher'
require_relative 'ext'
require_relative 'events'

module Datadog
  module Tracing
    module Contrib
      module Kafka
        # Patcher enables patching of 'kafka' module.
        module Patcher
          include Contrib::Patcher

          module_function

          def target_version
            Integration.version
          end

          def patch
            # Subscribe to Kafka events for tracing spans. This is skipped when tracing is
            # disabled (e.g. `DD_TRACE_KAFKA_ENABLED=false`), while the DSM instrumentation
            # below is still applied so Data Streams Monitoring keeps working.
            Events.subscribe! if Datadog.configuration.tracing[:kafka].enabled

            # Apply monkey patches for additional instrumentation (e.g., DSM). These
            # self-guard on `Datadog::DataStreams.enabled?`, so they are inert unless DSM
            # is enabled, independent of whether tracing is enabled.
            patch_producer if defined?(::Kafka::Producer)
            patch_consumer if defined?(::Kafka::Consumer)
          end

          def patch_producer
            require_relative 'instrumentation/producer'
            ::Kafka::Producer.prepend(Instrumentation::Producer)
          end

          def patch_consumer
            require_relative 'instrumentation/consumer'
            ::Kafka::Consumer.prepend(Instrumentation::Consumer)
          end
        end
      end
    end
  end
end
