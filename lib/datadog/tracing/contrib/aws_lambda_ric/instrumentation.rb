# frozen_string_literal: true

require_relative '../../metadata/ext'
require_relative '../analytics'
require_relative '../ext'
require_relative 'ext'

module Datadog
  module Tracing
    module Contrib
      module AwsLambdaRic
        # AWS Lambda RIC instrumentation module
        module Instrumentation
          def self.included(base)
            base.prepend(InstanceMethods)
          end

          # Instance methods for AWS Lambda RIC classes
          module InstanceMethods
            def run_user_code
              return super unless enabled?

              # Store the arguments for later use in the trace
              @lambda_user_code_args = method(__method__).super_method.parameters.map do |type, name|
                [type, name, binding.local_variable_get(name)] if binding.local_variable_defined?(name)
              end.compact

              super
            end

            def call_handler(request:, context:)
              return super unless enabled?

              # Store the arguments for later use in the trace
              @lambda_call_handler_args = { request: request, context: context }

              # Start the trace when the handler is called
              start_lambda_trace
              result = super
              # Store the result for later use in the trace
              @lambda_handler_result = result
              # Finish the trace when the handler completes
              finish_lambda_trace
              result
            end

            private

            def start_lambda_trace
              service = datadog_configuration[:service_name]
              on_error = datadog_configuration[:on_error]

              # Start a new span manually
              @lambda_span = Tracing.start_span(
                Ext::SPAN_COMMAND,
                service: service,
                resource: 'lambda_execution',
                type: Tracing::Metadata::Ext::HTTP::TYPE_INBOUND
              )

              annotate_span!(@lambda_span, 'lambda_execution')

              # Set analytics sample rate
              Contrib::Analytics.set_sample_rate(@lambda_span, analytics_sample_rate) if analytics_enabled?

              # Set error handler
              @lambda_span.on_error = on_error if on_error
            end

            def finish_lambda_trace
              return unless @lambda_span

              # Add any additional tags or metadata before finishing
              if @lambda_user_code_args
                @lambda_span.set_tag('lambda.user_code_args', @lambda_user_code_args.to_json)
              end

              if @lambda_call_handler_args
                @lambda_span.set_tag('lambda.call_handler.request', @lambda_call_handler_args[:request].to_json)
                @lambda_span.set_tag('lambda.call_handler.context', @lambda_call_handler_args[:context].to_json)
              end

              if @lambda_handler_result
                handler_response, content_type = @lambda_handler_result
                @lambda_span.set_tag('lambda.handler_response', handler_response.to_json)
                @lambda_span.set_tag('lambda.content_type', content_type.to_json) if content_type
              end

              # Finish the span
              @lambda_span.finish

              # Clean up instance variables
              @lambda_span = nil
              @lambda_user_code_args = nil
              @lambda_call_handler_args = nil
              @lambda_handler_result = nil
            end

            def annotate_span!(span, operation)
              span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_DEFAULT_AGENT)
              span.set_tag(Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION)
              span.set_tag(Tracing::Metadata::Ext::TAG_KIND, Tracing::Metadata::Ext::SpanKind::TAG_SERVER)

              # Add AWS Lambda specific tags
              span.set_tag(Ext::TAG_FUNCTION_NAME, function_name) if respond_to?(:function_name)
              span.set_tag(Ext::TAG_AWS_REGION, aws_region) if respond_to?(:aws_region)
              span.set_tag(Ext::TAG_AWS_ACCOUNT, aws_account) if respond_to?(:aws_account)

              # Tag original global service name if not used
              if span.service != Datadog.configuration.service
                span.set_tag(Tracing::Contrib::Ext::Metadata::TAG_BASE_SERVICE, Datadog.configuration.service)
              end

              Contrib::SpanAttributeSchema.set_peer_service!(span, Ext::PEER_SERVICE_SOURCES)
            end

            def datadog_configuration
              Datadog.configuration.tracing[:aws_lambda_ric]
            end

            def analytics_enabled?
              datadog_configuration[:analytics_enabled]
            end

            def analytics_sample_rate
              datadog_configuration[:analytics_sample_rate]
            end

            def enabled?
              datadog_configuration[:enabled]
            end
          end
        end
      end
    end
  end
end
