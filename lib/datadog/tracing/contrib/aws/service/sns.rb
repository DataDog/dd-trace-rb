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

            # Endpoint and platform application ARNs carry a `/`, and
            # subscription ARNs append `:<id>` to the topic.
            # @see https://docs.aws.amazon.com/service-authorization/latest/reference/list_amazonsns.html
            TOPIC_RESOURCE_FORMAT = %r{\A(?<name>[^:/]+)\z}

            def add_tags(span, params)
              topic_name, topic_arn, account_id = parse_topic_arn(params[:topic_arn])
              topic_name ||= params[:name]

              span.set_tag(Aws::Ext::TAG_TOPIC_ARN, topic_arn) if topic_arn
              span.set_tag(Aws::Ext::TAG_AWS_ACCOUNT, account_id) if account_id
              span.set_tag(Aws::Ext::TAG_TOPIC_NAME, topic_name)
              return if topic_name.nil? || topic_name == ""

              span.set_tag(Aws::Ext::TAG_AWS_TOPIC_NAME, topic_name)
            end

            private

            def parse_topic_arn(value)
              arn = Aws::Arn.parse(value)
              name = arn&.resource_name(SERVICE, TOPIC_RESOURCE_FORMAT)
              return unless arn && name

              [name, value, arn.account_id]
            end
          end
        end
      end
    end
  end
end
