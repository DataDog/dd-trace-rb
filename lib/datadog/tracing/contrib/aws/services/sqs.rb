# frozen_string_literal: true

require_relative '../ext'

def add_sqs_tags(span, params)
  queue_url = params[:queue_url]
  queue_name = params[:queue_name]
  if queue_url
    _, _, _, aws_account, queue_name = queue_url.split('/')
    span.set_tag(Datadog::Tracing::Contrib::Aws::Ext::TAG_AWS_ACCOUNT, aws_account)
  end
  span.set_tag(Datadog::Tracing::Contrib::Aws::Ext::TAG_QUEUE_NAME, queue_name)
end
