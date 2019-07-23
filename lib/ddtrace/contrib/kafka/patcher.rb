require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/kafka/producer'

module Datadog
  module Contrib
    module Kafka
      # Patcher enables patching of 'ruby-kafka' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def patched?
          done?(:kafka)
        end

        def patch
          do_once(:kafka) do
            begin
              patch_kafka_client
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply kafka integration: #{e}")
            end
          end
        end

        def patch_kafka_client
          ::Kafka::Producer.send(:include, Producer)
        end
      end
    end
  end
end
