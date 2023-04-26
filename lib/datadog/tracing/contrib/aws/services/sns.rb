# frozen_string_literal: true

require_relative '../ext'
require 'aws-sdk'

def add_sns_tags(span, params)
  topic_arn = params[:topic_arn]
  topic_name = params[:name]

  if topic_arn
    arn = Aws::ARNParser.parse(topic_arn)
    topic_name = arn.resource.split(':').last
    aws_account = arn.account_id
    span.set_tag(Datadog::Tracing::Contrib::Aws::Ext::TAG_AWS_ACCOUNT, aws_account)
  end

  span.set_tag(Datadog::Tracing::Contrib::Aws::Ext::TAG_TOPIC_NAME, topic_name)
end
