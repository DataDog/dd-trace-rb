# frozen_string_literal: true

require "json"

require_relative "../../../lambda"
require_relative "../../../appsec/contrib/aws_lambda/instrumentation"
require_relative "../../metadata/ext"
require_relative "ext"
require_relative "late_activation"
require_relative "lifecycle"

module Datadog
  module Tracing
    module Contrib
      module AwsLambdaRic
        # Traces the RIC boundary around each user handler invocation.
        module Instrumentation
          # rubocop:disable Lint/RescueException
          def call_handler(request:, context:)
            LateActivation.patch!
            request_id = context.aws_request_id
            continue_from = Lifecycle.start(request, request_id)
            cold_start = Lifecycle.claim_cold_start
            result = nil
            error = nil

            Tracing.trace(
              Ext::SPAN_NAME,
              continue_from: continue_from,
              on_error: error_handler,
              resource: Ext::SPAN_RESOURCE,
              service: "aws.lambda",
              type: Ext::SPAN_TYPE,
            ) do |span, trace|
              set_tags(span, trace, context, cold_start)

              begin
                result = invoke_with_appsec(request, trace, span, cold_start) { super }
              rescue Exception => e
                error = unwrap_error(e)
                raise
              ensure
                result = finish_appsec(result)
                span.resource = Ext::SPAN_RESOURCE
                trace_digest = trace.to_digest
                Datadog::Lambda.send(:record_trace_context, trace_digest)
                Lifecycle.finish(
                  result,
                  span: span,
                  request_id: request_id,
                  error: error,
                  trace_digest: trace_digest,
                )
              end

              result
            end
          end
          # rubocop:enable Lint/RescueException

          private

          def invoke_with_appsec(request, trace, span, cold_start)
            override = Datadog::AppSec::Contrib::AwsLambda::Instrumentation.on_start(
              request,
              trace: trace,
              span: span,
              cold_start: cold_start,
            )
            response = override || Datadog::AppSec::Contrib::AwsLambda::Instrumentation.catch_interrupt { yield }
            override ? marshall_response(response) : response
          end

          def finish_appsec(result)
            response = parse_response(result)
            override = Datadog::AppSec::Contrib::AwsLambda::Instrumentation.on_finish(response)
            override ? marshall_response(override) : result
          rescue => e
            Datadog.logger.debug do
              "Failed to finish AppSec for an AWS Lambda invocation: #{e.class}: #{e.message}"
            end
            result
          end

          def marshall_response(response)
            ::AwsLambda::Marshaller.marshall_response(response)
          end

          def parse_response(response)
            response = response.first if response.is_a?(Array)
            return response unless response.is_a?(String)

            JSON.parse(response)
          rescue JSON::ParserError
            nil
          end

          def error_handler
            configured = configuration[:on_error]
            lambda do |span, error|
              error = unwrap_error(error)
              configured ? configured.call(span, error) : span.set_error(error)
            end
          end

          def unwrap_error(error)
            if defined?(::LambdaErrors::LambdaError) && error.is_a?(::LambdaErrors::LambdaError) && error.cause
              error.cause
            else
              error
            end
          end

          def set_tags(span, trace, context, cold_start)
            trace.origin = "lambda"
            span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT)
            span.set_tag(Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION_INVOKE)
            span.set_tag(Tracing::Metadata::Ext::TAG_KIND, Tracing::Metadata::Ext::SpanKind::TAG_SERVER)
            span.set_tag(Ext::TAG_REQUEST_ID, context.aws_request_id)
            span.set_tag(Ext::TAG_FUNCTION_NAME, context.function_name.to_s.downcase)
            span.set_tag(Ext::TAG_FUNCTION_ARN, truncate_function_arn(context.invoked_function_arn))
            span.set_tag(Ext::TAG_FUNCTION_VERSION, context.function_version)
            span.set_tag(Ext::TAG_DD_TRACE, Datadog::VERSION::STRING)
            span.set_tag("cold_start", cold_start)
          end

          def truncate_function_arn(arn)
            parts = arn.to_s.downcase.split(":")
            if parts.length > 7
              parts[0, 7].join(":")
            else
              arn.to_s.downcase
            end
          end

          def configuration
            Datadog.configuration.tracing[:aws_lambda_ric]
          end
        end
      end
    end
  end
end
