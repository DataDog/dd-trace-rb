# frozen_string_literal: true

module Datadog
  module AppSec
    module Contrib
      module AwsLambda
        # Normalizes API Gateway proxy responses for the AWS Lambda gateway watchers.
        module ResponseNormalizer
          module_function

          def normalize(response)
            return {} unless response.is_a?(Hash)

            data = {
              "status_code" => response["statusCode"],
              "headers" => merge_headers(response),
              "body" => response["body"],
              "base64_encoded" => response["isBase64Encoded"],
            }
            data.delete_if { |_key, value| value.nil? }
          end

          def merge_headers(response)
            headers = response["headers"]
            multi_headers = response["multiValueHeaders"]

            return headers unless multi_headers
            return multi_headers unless headers

            headers.merge(multi_headers)
          end
        end
      end
    end
  end
end
