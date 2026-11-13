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

            def add_tags(span, params)
              topic_name, topic_arn, account_id = parse_topic_arn(params[:topic_arn])
              topic_name ||= params[:name]

              span.set_tag(Aws::Ext::TAG_AWS_TOPIC_ARN, topic_arn) if topic_arn
              span.set_tag(Aws::Ext::TAG_AWS_ACCOUNT, account_id) if account_id
              span.set_tag(Aws::Ext::TAG_TOPIC_NAME, topic_name)
              return if topic_name.nil? || topic_name == ""

              span.set_tag(Aws::Ext::TAG_AWS_TOPIC_NAME, topic_name)
            end

            private

            # Returns the topic name, ARN and account of a topic ARN
            # (`arn:aws:sns:us-west-2:123456789012:my-topic`), or `nil` when
            # `value` is not one. Endpoint, platform application and
            # subscription ARNs carry a further resource segment, so they are
            # not topic ARNs.
            def parse_topic_arn(value)
              arn = Aws::Arn.parse(value)
              name = arn&.bare_resource_id(SERVICE)
              return unless arn && name

              [name, value, arn.account_id]
            end
          end
        end
      end
    end
  end
end
