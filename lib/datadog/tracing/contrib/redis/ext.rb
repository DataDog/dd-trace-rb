# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module Redis
        # Redis integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          ENV_ENABLED = 'DD_TRACE_REDIS_ENABLED'
          ENV_SERVICE_NAME = 'DD_TRACE_REDIS_SERVICE_NAME'
          ENV_PEER_SERVICE = 'DD_TRACE_REDIS_PEER_SERVICE'
          # @!visibility private
          ENV_ANALYTICS_ENABLED = 'DD_TRACE_REDIS_ANALYTICS_ENABLED'
          ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_REDIS_ANALYTICS_SAMPLE_RATE'
          ENV_COMMAND_ARGS = 'DD_REDIS_COMMAND_ARGS'
          METRIC_PIPELINE_LEN = 'redis.pipeline_length'
          DEFAULT_PEER_SERVICE_NAME = 'redis'
          SPAN_COMMAND = 'redis.command'
          TAG_DB = 'out.redis_db'
          TAG_RAW_COMMAND = 'redis.raw_command'
          ### BRAZE MODIFICATION
          METRIC_RAW_COMMAND_LEN = 'redis.raw_command_length'.freeze
          METRIC_RESP_COMMAND_LEN = 'redis.raw_response_length'.freeze
          METRIC_FILEPATH = 'redis.filepath'.freeze
          METRIC_CODEOWNER = 'redis.codeowner'.freeze
          METRIC_SHARD_INDEX = 'redis.shard_index'.freeze
          METRIC_KEY = 'redis.key'.freeze
          THREAD_GLOBAL_FILEPATH = :redis_operation_filepath
          THREAD_GLOBAL_CODEOWNER = :redis_operation_codeowner
          THREAD_GLOBAL_SHARD_INDEX = :redis_operation_shard_index
          ### END BRAZE MODIFICATION
          TYPE = 'redis'
          TAG_COMPONENT = 'redis'
          TAG_OPERATION_COMMAND = 'command'
          TAG_SYSTEM = 'redis'
          TAG_DATABASE_INDEX = 'db.redis.database_index'
          PEER_SERVICE_SOURCES = Array[
            Tracing::Metadata::Ext::TAG_PEER_HOSTNAME,
            Tracing::Metadata::Ext::NET::TAG_DESTINATION_NAME,
            Tracing::Metadata::Ext::NET::TAG_TARGET_HOST,].freeze
        end
      end
    end
  end
end
