# frozen_string_literal: true

require_relative "base"
require_relative "../arn"
require_relative "../ext"

module Datadog
  module Tracing
    module Contrib
      module Aws
        module Service
          # SNS tag handlers.
          class SNS < Base
            SERVICE = "sns"

            # A topic ARN is the one SNS ARN with a bare-name resource
            # (`arn:aws:sns:us-west-2:123456789012:my-topic`); endpoint,
            # platform application and subscription ARNs carry a further
            # segment. Reading only `topic_arn` (never `Publish`'s `TargetArn`)
            # and requiring a bare resource keeps those from being tagged as a
            # topic.
            def add_tags(span, params)
              topic_arn = params[:topic_arn]
              topic_name = params[:name]

              arn = Aws::Arn.parse(topic_arn)
              resolved_name = arn&.bare_resource_id(SERVICE)

              if arn && resolved_name
                topic_name = resolved_name
                account_id = arn.account_id
                span.set_tag(Aws::Ext::TAG_AWS_TOPIC_ARN, topic_arn)
                span.set_tag(Aws::Ext::TAG_AWS_ACCOUNT, account_id) if account_id
              end

              span.set_tag(Aws::Ext::TAG_TOPIC_NAME, topic_name)
              set_resolved_name(span, Aws::Ext::TAG_AWS_TOPIC_NAME, topic_name)
            end
          end
        end
      end
    end
  end
end
