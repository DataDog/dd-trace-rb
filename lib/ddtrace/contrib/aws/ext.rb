module Datadog
  module Contrib
    module Aws
      # AWS integration constants
      module Ext
        APP = 'aws'.freeze
        ENV_ENABLED = 'DD_TRACE_AWS_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_TRACE_AWS_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED_OLD = 'DD_AWS_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_AWS_ANALYTICS_SAMPLE_RATE'.freeze
        ENV_ANALYTICS_SAMPLE_RATE_OLD = 'DD_AWS_ANALYTICS_SAMPLE_RATE'.freeze
        SERVICE_NAME = 'aws'.freeze
        SPAN_COMMAND = 'aws.command'.freeze
        TAG_AGENT = 'aws.agent'.freeze
        TAG_DEFAULT_AGENT = 'aws-sdk-ruby'.freeze
        TAG_HOST = 'host'.freeze
        TAG_OPERATION = 'aws.operation'.freeze
        TAG_PATH = 'path'.freeze
        TAG_REGION = 'aws.region'.freeze
      end
    end
  end
end
