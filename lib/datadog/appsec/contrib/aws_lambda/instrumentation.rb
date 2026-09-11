# frozen_string_literal: true

require_relative "../../api_security"
require_relative "../../event"
require_relative "../../instrumentation/gateway"
require_relative "../../instrumentation/gateway/argument"
require_relative "event_normalizer"
require_relative "request"
require_relative "response"
require_relative "response_normalizer"
require_relative "tagging"

module Datadog
  module AppSec
    module Contrib
      module AwsLambda
        # Manages the AppSec context around one Lambda handler invocation.
        module Instrumentation
          class << self
            def on_start(event, trace:, span:, cold_start: false)
              context = nil
              return unless enabled?

              context = create_context(trace, span)
              return unless context

              Tagging.tag_and_keep(context, cold_start: cold_start)
              normalized = EventNormalizer.normalize(event)
              request = Request.from_normalized(normalized)
              context.state[:aws_lambda_request] = request
              Tagging.tag_request(request, context: context)

              interrupt = catch(Ext::INTERRUPT) do
                payload = AppSec::Instrumentation::Gateway::DataContainer.new(normalized, context: context)
                AppSec::Instrumentation.gateway.push("aws_lambda.request.start", payload)
                nil
              end
              return unless interrupt

              context.mark_as_interrupted!
              response_override(interrupt, headers: request.headers)
            rescue => e
              deactivate_context if context
              log_failure("start", e)
              nil
            end

            def on_finish(handler_response)
              return unless enabled?

              context = Context.active
              return unless context

              finish_context(context, handler_response)
            rescue => e
              log_failure("finish", e)
              nil
            end

            def catch_interrupt
              interrupt = catch(Ext::INTERRUPT) { return yield }
              context = Context.active
              context&.mark_as_interrupted!
              request = context&.state&.[](:aws_lambda_request)
              response_override(interrupt, headers: request ? request.headers : {})
            end

            private

            def finish_context(context, handler_response)
              request = context.state[:aws_lambda_request]
              normalized = ResponseNormalizer.normalize(handler_response)
              response = Response.from_normalized(normalized)
              interrupt = inspect_response(context, normalized, response)
              extract_api_security_schema(context, request: request, response: response)
              Event.record(context, request: request)

              response_override(interrupt, headers: request ? request.headers : {}) if interrupt
            ensure
              finalize_context(context)
            end

            def enabled?
              AppSec.enabled?
            end

            def create_context(trace, span)
              return if trace.nil? || span.nil?

              security_engine = AppSec.security_engine
              return unless security_engine

              context = Context.new(trace, span, security_engine.new_runner)
              Context.activate(context)
              context
            end

            def inspect_response(context, normalized, response)
              return if context.interrupted?

              Tagging.tag_response(response, context: context)
              payload = AppSec::Instrumentation::Gateway::DataContainer.new(normalized, context: context)
              interrupt = catch(Ext::INTERRUPT) do
                AppSec::Instrumentation.gateway.push("aws_lambda.response.start", payload)
                nil
              end
              context.mark_as_interrupted! if interrupt
              interrupt
            end

            def extract_api_security_schema(context, request:, response:)
              return unless request && response
              return unless APISecurity.enabled? && APISecurity.sample_trace?(context.trace)
              return unless api_security_sample?(request, response)

              context.extract_schema!
            end

            def api_security_sample?(request, response)
              APISecurity.sample?(request, response)
            end

            def response_override(interrupt, headers:)
              response = AppSec::Response.from_interrupt_params(interrupt, headers["accept"])
              {
                "statusCode" => response.status,
                "headers" => response.headers,
                "body" => response.body.join,
              }
            end

            def finalize_context(context)
              begin
                context.export_metrics
              rescue => e
                log_failure("metric export", e)
              end

              begin
                context.export_request_telemetry
              rescue => e
                log_failure("request telemetry export", e)
              end

              deactivate_context
            end

            def deactivate_context
              Context.deactivate
            rescue => e
              log_failure("context deactivation", e)
            end

            def log_failure(stage, error)
              Datadog.logger.debug do
                "AWS Lambda AppSec #{stage} failed: #{error.class}: #{error.message}"
              end
            end
          end
        end
      end
    end
  end
end
