module Datadog
  module Contrib
    module Aws
      # AWS integration constants
      module Ext
        APP = 'aws'.freeze
        SERVICE_NAME = 'aws'.freeze

        SPAN_COMMAND = 'aws.command'.freeze

        TAG_AGENT = 'aws.agent'.freeze
        TAG_OPERATION = 'aws.operation'.freeze
        TAG_REGION = 'aws.region'.freeze
        TAG_PATH = 'path'.freeze
        TAG_HOST = 'host'.freeze

        TAG_DEFAULT_AGENT = 'aws-sdk-ruby'.freeze
      end
    end
  end
end
