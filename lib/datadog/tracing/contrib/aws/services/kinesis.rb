def add_kinesis_tags(span, params)
    stream_arn = params[:stream_arn]
    stream_name = params[:stream_name]
    if stream_arn
      # example stream_arn: arn:aws:kinesis:us-east-1:123456789012:stream/my-stream
      parts = stream_arn.split(':')
      stream_name = parts[-1]
      aws_account = parts[-2]
      span.set_tag(Ext::TAG_AWS_ACCOUNT, aws_account)
    end
    span.set_tag(Ext::TAG_STREAM_NAME, stream_name)
end