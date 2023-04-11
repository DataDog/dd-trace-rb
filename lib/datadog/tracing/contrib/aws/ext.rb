# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module Aws
        # AWS integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          ENV_ENABLED = 'DD_TRACE_AWS_ENABLED'
          ENV_SERVICE_NAME = 'DD_TRACE_AWS_SERVICE_NAME'
          ENV_ANALYTICS_ENABLED = 'DD_TRACE_AWS_ANALYTICS_ENABLED'
          ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_AWS_ANALYTICS_SAMPLE_RATE'
          DEFAULT_PEER_SERVICE_NAME = 'aws'
          SPAN_COMMAND = 'aws.command'
          TAG_AGENT = 'aws.agent'
          TAG_COMPONENT = 'aws'
          TAG_DEFAULT_AGENT = 'aws-sdk-ruby'
          TAG_HOST = 'host'
          TAG_OPERATION = 'aws.operation'
          TAG_OPERATION_COMMAND = 'command'
          TAG_PATH = 'path'
          TAG_REGION = 'aws.region'
        end
      end
    end
  end
end
