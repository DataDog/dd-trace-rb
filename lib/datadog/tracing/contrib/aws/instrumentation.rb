require_relative '../../metadata/ext'
require_relative '../analytics'
require_relative 'ext'

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
          def call(context)
            Tracing.trace(Ext::SPAN_COMMAND) do |span|
              @handler.call(context).tap do
                annotate!(span, ParsedContext.new(context))
              end
            end
          end

          private

          def annotate!(span, context)
            span.service = configuration[:service_name]
            span.span_type = Tracing::Metadata::Ext::HTTP::TYPE_OUTBOUND
            span.name = Ext::SPAN_COMMAND
            span.resource = context.safely(:resource)
            aws_service = span.resource.split('.')[0]
            span.set_tag(Ext::TAG_AWS_SERVICE, aws_service)
            params = context.safely(:params)
            add_service_specific_tags(span, aws_service, params)

            span.set_tag(Tracing::Metadata::Ext::TAG_KIND, Tracing::Metadata::Ext::SpanKind::TAG_CLIENT)

            span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT)
            span.set_tag(Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION_COMMAND)

            # Tag as an external peer service
            span.set_tag(Tracing::Metadata::Ext::TAG_PEER_SERVICE, span.service)
            span.set_tag(Tracing::Metadata::Ext::TAG_PEER_HOSTNAME, context.safely(:host))

            # Set analytics sample rate
            if Contrib::Analytics.enabled?(configuration[:analytics_enabled])
              Contrib::Analytics.set_sample_rate(span, configuration[:analytics_sample_rate])
            end
            Contrib::Analytics.set_measured(span)

            span.set_tag(Ext::TAG_AGENT, Ext::TAG_DEFAULT_AGENT)
            span.set_tag(Ext::TAG_OPERATION, context.safely(:operation))
            span.set_tag(Ext::TAG_REGION, context.safely(:region))
            span.set_tag(Ext::TAG_PATH, context.safely(:path))
            span.set_tag(Ext::TAG_HOST, context.safely(:host))
            span.set_tag(Tracing::Metadata::Ext::HTTP::TAG_METHOD, context.safely(:http_method))
            span.set_tag(Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE, context.safely(:status_code))
          end

          def add_service_specific_tags(span, aws_service, params)
            case aws_service
            when 'sqs'
              add_sqs_tags(span, params)
            when 'sns'
              add_sns_tags(span, params)
            when 'dynamodb'
              add_dynamodb_tags(span, params)
            when 'kinesis'
              add_kinesis_tags(span, params)
            when 'eventbridge'
              add_eventbridge_tags(span, params)
            when 'states'
              add_states_tags(span, params)
            when 's3'
              add_s3_tags(span, params)
            end
          end

          def add_sqs_tags(span, params)
            queue_url = params.fetch(:queue_url, nil)
            queue_name = params.fetch(:queue_name, nil)
            if queue_url
              # example queue_url: https://sqs.sa-east-1.amazonaws.com/12345678/MyQueueName
              queue_name = queue_url.split('/')[-1]
              aws_account = queue_url.split('/')[-2]
              span.set_tag(Ext::TAG_AWS_ACCOUNT, aws_account)
            end
            span.set_tag(Ext::TAG_QUEUE_NAME, queue_name)
          end

          def add_sns_tags(span, params)
            topic_arn = params.fetch(:topic_arn, nil)
            topic_name = params.fetch(:name, nil)
            if topic_arn
              # example topic_arn: arn:aws:sns:us-west-2:123456789012:my-topic-name
              topic_name = topic_arn.split(':')[-1]
              aws_account = topic_arn.split(':')[-2]
              span.set_tag(Ext::TAG_AWS_ACCOUNT, aws_account)
            end
            span.set_tag(Ext::TAG_TOPIC_NAME, topic_name)
          end

          def add_dynamodb_tags(span, params)
            table_name = params.fetch(:table_name, '')
            span.set_tag(Ext::TAG_TABLE_NAME, table_name)
          end

          def add_kinesis_tags(span, params)
            stream_arn = params.fetch(:stream_arn, nil)
            stream_name = params.fetch(:stream_name, '')
            if stream_arn
              # example stream_arn: arn:aws:kinesis:us-east-1:123456789012:stream/my-stream
              stream_name = stream_arn.split('/')[-1] rescue ''
              aws_account = stream_arn.split(':')[-2] rescue ''
              span.set_tag(Ext::TAG_AWS_ACCOUNT, aws_account)
            end
            span.set_tag(Ext::TAG_STREAM_NAME, stream_name)
          end

          def add_eventbridge_tags(span, params)
            rule_name = params.fetch(:name, nil) || params.fetch(:rule, nil)
            span.set_tag(Ext::TAG_RULE_NAME, rule_name)
          end

          def add_states_tags(span, params)
            state_machine_name = params.fetch(:name, nil)
            state_machine_arn = params.fetch(:state_machine_arn, nil)
            execution_arn = params.fetch(:execution_arn, nil)

            if execution_arn
              # 'arn:aws:states:us-east-1:123456789012:execution:example-state-machine:example-execution'
              state_machine_name = execution_arn.split(':')[-2]
            end

            if state_machine_arn
              # example statemachinearn: arn:aws:states:us-east-1:123456789012:stateMachine:MyStateMachine
              state_machine_name = state_machine_arn.split(':')[-1]
              state_machine_account_id = state_machine_arn.split(':')[-3]
            end
            span.set_tag(Ext::TAG_AWS_ACCOUNT, state_machine_account_id)
            # state_machine_name = create_state_machine_name || start_execution_state_machine_name
            span.set_tag(Ext::TAG_STATE_MACHINE_NAME, state_machine_name)
          end

          def add_s3_tags(span, params)
            bucket_name = params.fetch(:bucket, nil)
            span.set_tag(Ext::TAG_BUCKET_NAME, bucket_name)
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
