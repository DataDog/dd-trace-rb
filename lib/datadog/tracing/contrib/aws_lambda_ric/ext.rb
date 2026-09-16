# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module AwsLambdaRic
        # AWS Lambda Runtime Interface Client integration constants.
        # @public_api Changing span or tag names creates breaking changes.
        module Ext
          SPAN_NAME = "aws.lambda"
          SPAN_TYPE = "serverless"
          SPAN_RESOURCE = "dd-tracer-serverless-span"

          TAG_COMPONENT = "aws_lambda_ric"
          TAG_OPERATION_INVOKE = "invoke"
          TAG_FUNCTION_ARN = "function_arn"
          TAG_FUNCTION_NAME = "functionname"
          TAG_FUNCTION_VERSION = "function_version"
          TAG_REQUEST_ID = "request_id"
          TAG_DD_TRACE = "dd_trace"

          EXTENSION_PATH = "/opt/extensions/datadog-agent"
          EXTENSION_HOST = "127.0.0.1"
          EXTENSION_PORT = 8124
          START_INVOCATION_PATH = "/lambda/start-invocation"
          END_INVOCATION_PATH = "/lambda/end-invocation"

          HEADER_REQUEST_ID = "lambda-runtime-aws-request-id"
          HEADER_SPAN_ID = "x-datadog-span-id"
          HEADER_INVOCATION_ERROR = "x-datadog-invocation-error"
          HEADER_INVOCATION_ERROR_MESSAGE = "x-datadog-invocation-error-msg"
          HEADER_INVOCATION_ERROR_TYPE = "x-datadog-invocation-error-type"
          HEADER_INVOCATION_ERROR_STACK = "x-datadog-invocation-error-stack"
        end
      end
    end
  end
end
