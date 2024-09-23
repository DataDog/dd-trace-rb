# frozen_string_literal: true

require_relative '../../metadata/ext'
require_relative '../analytics'
require_relative 'ext'
require_relative '../span_attribute_schema'

module Datadog
  module Tracing
    module Contrib
      module Aws
        # A Seahorse::Client::Plugin that enables instrumentation for all AWS services
        class Instrumentation < Seahorse::Client::Plugin
          def add_handlers(handlers, _)
            handlers.add(Handler, step: :validate)
          end
        end

        # Generates Spans for all interactions with AWS
        class Handler < Seahorse::Client::Handler
          # Some services contain trace propagation information (e.g. SQS) that affect what active trace
          # we'll use for the AWS span.
          # But because this information is only available after the request is made, we need to make the AWS
          # request first, then create the trace and span with correct distributed trace parenting.
          def call(context)
            config = configuration

            # Find the AWS service instrumentation
            parsed_context = ParsedContext.new(context)
            aws_service = parsed_context.safely(:resource).split('.')[0]
            handler = Datadog::Tracing::Contrib::Aws::SERVICE_HANDLERS[aws_service]

            # Execute handler stack, to ensure we have the response object before the trace and span are created
            start_time = Core::Utils::Time.now.utc # Save the start time as the span creation is delayed
            begin
              response = @handler.call(context)
            rescue Exception => e # rubocop:disable Lint/RescueException
              # Catch exception to reraise it inside the trace block, to ensure the span has correct error information
              # This matches the behavior of {Datadog::Tracing::SpanOperation#measure}
            end

            Tracing.trace(Ext::SPAN_COMMAND, start_time: start_time) do |span, trace|
              handler.before_span(config, context, response) if handler

              annotate!(config, span, trace, parsed_context, aws_service)

              raise e if e
            end

            response
          end

          private

          def annotate!(config, span, trace, context, aws_service)
            span.service = config[:service_name]
            span.type = Tracing::Metadata::Ext::HTTP::TYPE_OUTBOUND
            span.name = Ext::SPAN_COMMAND
            span.resource = context.safely(:resource)
            span.set_tag(Ext::TAG_AWS_SERVICE, aws_service)
            params = context.safely(:params)
            if (handler = Datadog::Tracing::Contrib::Aws::SERVICE_HANDLERS[aws_service])
              handler.process(config, trace, context)
              handler.add_tags(span, params)
            end

            if config[:peer_service]
              span.set_tag(
                Tracing::Metadata::Ext::TAG_PEER_SERVICE,
                config[:peer_service]
              )
            end

            # Tag original global service name if not used
            if span.service != Datadog.configuration.service
              span.set_tag(Tracing::Contrib::Ext::Metadata::TAG_BASE_SERVICE, Datadog.configuration.service)
            end

            span.set_tag(Tracing::Metadata::Ext::TAG_KIND, Tracing::Metadata::Ext::SpanKind::TAG_CLIENT)

            span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT)
            span.set_tag(Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION_COMMAND)

            span.set_tag(Tracing::Metadata::Ext::TAG_PEER_HOSTNAME, context.safely(:host))

            # Set analytics sample rate
            if Contrib::Analytics.enabled?(config[:analytics_enabled])
              Contrib::Analytics.set_sample_rate(span, config[:analytics_sample_rate])
            end
            Contrib::Analytics.set_measured(span)

            span.set_tag(Ext::TAG_AGENT, Ext::TAG_DEFAULT_AGENT)
            span.set_tag(Ext::TAG_OPERATION, context.safely(:operation))
            span.set_tag(Ext::TAG_REGION, context.safely(:region))
            span.set_tag(Ext::TAG_AWS_REGION, context.safely(:region))
            span.set_tag(Ext::TAG_PATH, context.safely(:path))
            span.set_tag(Ext::TAG_HOST, context.safely(:host))
            span.set_tag(Tracing::Metadata::Ext::HTTP::TAG_METHOD, context.safely(:http_method))
            span.set_tag(Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE, context.safely(:status_code))

            Contrib::SpanAttributeSchema.set_peer_service!(span, Ext::PEER_SERVICE_SOURCES)
          end

          def configuration
            Datadog.configuration.tracing[:aws]
          end
        end

        # Removes API request instrumentation from S3 Presign URL creation.
        #
        # This is necessary because the S3 SDK invokes the same handler
        # stack for presigning as it does for sending a real requests.
        # But presigning does not perform a network request.
        # There's not information available for our Handler plugin to differentiate
        # these two types of requests.
        #
        # DEV: Since aws-sdk-s3 1.94.1, we only need to check if
        # `context[:presigned_url] == true` in Datadog::Tracing::Contrib::Aws::Handler#call
        # and skip the request if that condition is true. Since there's
        # no strong reason for us not to support older versions of `aws-sdk-s3`,
        # this {S3Presigner} monkey-patching is still required.
        module S3Presigner
          # Exclude our Handler from the current request's handler stack.
          #
          # This is the same approach that the AWS SDK takes to prevent
          # some of its plugins form interfering with the presigning process:
          # https://github.com/aws/aws-sdk-ruby/blob/a82c8981c95a8296ffb6269c3c06a4f551d87f7d/gems/aws-sdk-s3/lib/aws-sdk-s3/presigner.rb#L194-L196
          def sign_but_dont_send(*args, &block)
            if (request = args[0]).is_a?(::Seahorse::Client::Request)
              request.handlers.remove(Handler)
            end

            super(*args, &block)
          end

          ruby2_keywords :sign_but_dont_send if respond_to?(:ruby2_keywords, true)
        end
      end
    end
  end
end
