# frozen_string_literal: true

require_relative '../ext'

def add_sns_tags(span, params)
  topic_arn = params[:topic_arn]
  topic_name = params[:name]
  if topic_arn
    # example topic_arn: arn:aws:sns:us-west-2:123456789012:my-topic-name
    parts = topic_arn.split(':')
    topic_name = parts[-1]
    aws_account = parts[-2]
    span.set_tag(Datadog::Tracing::Contrib::Aws::Ext::TAG_AWS_ACCOUNT, aws_account)
  end
  span.set_tag(Datadog::Tracing::Contrib::Aws::Ext::TAG_TOPIC_NAME, topic_name)
end