# frozen_string_literal: true

module Datadog
  module AppSec
    module Contrib
      module AwsLambda
        # Normalizes API Gateway proxy events for the AWS Lambda gateway watchers.
        module EventNormalizer
          module_function

          def normalize(event)
            return {} unless event.is_a?(Hash)

            event.key?("httpMethod") ? normalize_v1(event) : normalize_v2(event)
          end

          def normalize_v1(event)
            compact(
              "method" => event["httpMethod"],
              "path" => event["path"],
              "headers" => event["headers"],
              "query" => event["multiValueQueryStringParameters"] || event["queryStringParameters"],
              "source_ip" => event.dig("requestContext", "identity", "sourceIp"),
              "body" => event["body"],
              "base64_encoded" => event["isBase64Encoded"],
              "path_params" => event["pathParameters"],
            )
          end

          def normalize_v2(event)
            compact(
              "method" => event.dig("requestContext", "http", "method"),
              "path" => event["rawPath"],
              "headers" => event["headers"],
              "cookies" => event["cookies"],
              "query" => event["queryStringParameters"],
              "query_string" => event["rawQueryString"],
              "source_ip" => event.dig("requestContext", "http", "sourceIp"),
              "body" => event["body"],
              "base64_encoded" => event["isBase64Encoded"],
              "path_params" => event["pathParameters"],
            )
          end

          def compact(data)
            data.delete_if { |_key, value| value.nil? }
          end
        end
      end
    end
  end
end
