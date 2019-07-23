require 'ddtrace/ext/app_types'
require 'ddtrace/ext/net'
require 'ddtrace/ext/sql'
require 'ddtrace/contrib/kafka/ext'

module Datadog
  module Contrib
    module Kafka
      # Kafka::Producer patch module
      module Producer
        module_function

        def included(base)
          base.send(:prepend, InstanceMethods)
        end

        # Kafka::Producer patch instance methods
        module InstanceMethods

          # This will actually capture the time we spend producing data to Kafka in background
          # threads by Sidekiq/API workers.
          #
          # returns nothing, takes no args
          def deliver_messages
            if buffer_size == 0
              # don't bother tracing flushes with 0 in the buffer...
              super
            else
              datadog_pin.tracer.trace(Ext::SPAN_REQUEST) do |span|
                span.resource = 'deliver_messages'.freeze
                span.service = datadog_pin.service
                span.span_type = Datadog::Ext::AppTypes::CUSTOM
                span.set_tag(Ext::TAG_BUFFER_SIZE, buffer_size)
                span.set_tag(Ext::TAG_CLUSTER, @cluster.cluster_info)
                super # this will pass all args, including the block
              end
            end
          end

          # This will capture the number/type of messages being enqueued to be
          # processed by `deliver_messages` above as spans in application traces.
          #
          # @param value [String] the message data.
          # @param key [String] the message key.
          # @param headers [Hash<String, String>] the headers for the message.
          # @param topic [String] the topic that the message should be written to.
          # @param partition [Integer] the partition that the message should be written to.
          # @param partition_key [String] the key that should be used to assign a partition.
          # @param create_time [Time] the timestamp that should be set on the message.
          #
          # @raise [BufferOverflow] if the maximum buffer size has been reached.
          # @return [nil]
          def produce(value, key: nil, headers: {}, topic:, partition: nil, partition_key: nil, create_time: Time.now)
            datadog_pin.tracer.trace(Ext::SPAN_REQUEST) do |span|
              span.resource = topic.to_s
              span.service = datadog_pin.service
              span.span_type = Datadog::Ext::AppTypes::CUSTOM
              span.set_tag(Ext::TAG_PARTITION, partition)
              super # this will pass all args, including the block
            end
          end

          def datadog_pin
            @datadog_pin ||= Datadog::Pin.new(
              Datadog.configuration[:kafka][:service_name],
              app: Ext::APP,
              app_type: Datadog::Ext::AppTypes::CUSTOM,
              tracer: Datadog.configuration[:kafka][:tracer]
            )
          end
        end
      end
    end
  end
end
