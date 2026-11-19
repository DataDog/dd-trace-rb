# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module Karafka
        # Reads values from an rdkafka configuration hash, as used by Karafka and WaterDrop.
        module KafkaConfig
          # rdkafka accepts both Symbol and String keys.
          def self.bootstrap_servers(kafka_config)
            return unless kafka_config

            kafka_config[:"bootstrap.servers"] || kafka_config["bootstrap.servers"]
          end
        end
      end
    end
  end
end
