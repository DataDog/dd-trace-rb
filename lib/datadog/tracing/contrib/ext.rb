# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      # Contrib specific constants
      module Ext
        # @public_api
        module DB
          TAG_INSTANCE = 'db.instance'
          TAG_USER = 'db.user'
          TAG_SYSTEM = 'db.system'
          TAG_STATEMENT = 'db.statement'
          TAG_ROW_COUNT = 'db.row_count'
        end

        module RPC
          TAG_SYSTEM = 'rpc.system'
          TAG_SERVICE = 'rpc.service'
          TAG_METHOD = 'rpc.method'

          module GRPC
            TAG_STATUS_CODE = 'rpc.grpc.status_code'
            TAG_FULL_METHOD = 'rpc.grpc.full_method'
          end
        end

        module Messaging
          TAG_SYSTEM = 'messaging.system'
          TAG_RABBITMQ_ROUTING_KEY = 'messaging.rabbitmq.routing_key'
          TAG_KAFKA_BOOTSTRAP_SERVERS = 'messaging.kafka.bootstrap.servers'
        end

        module SpanAttributeSchema
          PEER_SERVICE_SOURCE_AWS = Array[Aws::Ext::TAG_QUEUE_NAME,
            Aws::Ext::TAG_TOPIC_NAME,
            Aws::Ext::TAG_STREAM_NAME,
            Aws::Ext::TAG_TABLE_NAME,
            Aws::Ext::TAG_BUCKET_NAME,
            Aws::Ext::TAG_RULE_NAME,
            Aws::Ext::TAG_STATE_MACHINE_NAME,]

          # TODO: consolidate all db.name tags to 1 tag name and add to array here
          PEER_SERVICE_SOURCE_DB = Array[Tracing::Contrib::Ext::DB::TAG_INSTANCE]

          # TODO: add kafka bootstrap servers tag
          PEER_SERVICE_SOURCE_MSG = Array[]

          PEER_SERVICE_SOURCE_RPC = Array[Tracing::Contrib::Ext::RPC::TAG_SERVICE]
        end
      end
    end
  end
end
