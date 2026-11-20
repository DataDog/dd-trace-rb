# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module Karafka
        # Reads values from an rdkafka configuration hash, as used by Karafka and WaterDrop.
        module KafkaConfig
          JOB_BOOTSTRAP_SERVERS_KEY = :datadog_karafka_job_bootstrap_servers
          private_constant :JOB_BOOTSTRAP_SERVERS_KEY

          # rdkafka accepts both Symbol and String keys.
          def self.bootstrap_servers(kafka_config)
            return unless kafka_config

            kafka_config[:"bootstrap.servers"] || kafka_config["bootstrap.servers"]
          end

          # The brokers of the routed topic the current worker job consumes. A topic may override
          # `bootstrap.servers` to consume from another cluster, and message batches do not keep
          # their routed topic, so the worker instrumentation passes them to the message spans.
          def self.with_job_bootstrap_servers(bootstrap_servers)
            previous = Thread.current[JOB_BOOTSTRAP_SERVERS_KEY]
            Thread.current[JOB_BOOTSTRAP_SERVERS_KEY] = bootstrap_servers
            yield
          ensure
            Thread.current[JOB_BOOTSTRAP_SERVERS_KEY] = previous
          end

          def self.job_bootstrap_servers
            Thread.current[JOB_BOOTSTRAP_SERVERS_KEY]
          end
        end
      end
    end
  end
end
