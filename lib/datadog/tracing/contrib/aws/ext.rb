module Datadog
  module Tracing
    module Contrib
      module Aws
        # AWS integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          ENV_ENABLED = 'DD_TRACE_AWS_ENABLED'.freeze
          ENV_SERVICE_NAME = 'DD_TRACE_AWS_SERVICE_NAME'.freeze
          ENV_ANALYTICS_ENABLED = 'DD_TRACE_AWS_ANALYTICS_ENABLED'.freeze
          ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_AWS_ANALYTICS_SAMPLE_RATE'.freeze
          DEFAULT_PEER_SERVICE_NAME = 'aws'.freeze
          SPAN_COMMAND = 'aws.command'.freeze
          TAG_AGENT = 'aws.agent'.freeze
          TAG_COMPONENT = 'aws'.freeze
          TAG_DEFAULT_AGENT = 'aws-sdk-ruby'.freeze
          TAG_HOST = 'host'.freeze
          TAG_OPERATION = 'aws.operation'.freeze
          TAG_OPERATION_COMMAND = 'command'.freeze
          TAG_PATH = 'path'.freeze
          TAG_AWS_REGION = 'aws.region'.freeze
          TAG_REGION = 'region'.freeze
          TAG_AWS_SERVICE = 'aws_service'.freeze
          TAG_AWS_ACCOUNT = 'aws_account'.freeze
          TAG_QUEUE_NAME = 'queuename'.freeze
          TAG_TOPIC_NAME = 'topicname'.freeze
          TAG_TABLE_NAME = 'tablename'.freeze
          TAG_STREAM_NAME = 'streamname'.freeze
          TAG_RULE_NAME = 'rulename'.freeze
          TAG_STATE_MACHINE_NAME = 'statemachinename'.freeze
          TAG_BUCKET_NAME = 'bucketname'.freeze
        end
      end
    end
  end
end
