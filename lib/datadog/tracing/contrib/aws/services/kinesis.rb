# frozen_string_literal: true

require_relative '../ext'
require 'aws-sdk'

def add_kinesis_tags(span, params)
  stream_arn = params[:stream_arn]
  stream_name = params[:stream_name]

  if stream_arn
    arn = Aws::ARNParser.parse(stream_arn)
    stream_name = arn.resource.split('/').last
    aws_account = arn.account_id
    span.set_tag(Datadog::Tracing::Contrib::Aws::Ext::TAG_AWS_ACCOUNT, aws_account)
  end

  span.set_tag(Datadog::Tracing::Contrib::Aws::Ext::TAG_STREAM_NAME, stream_name)
end
