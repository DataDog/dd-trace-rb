def add_sqs_tags(span, params)
    queue_url = params[:queue_url]
    queue_name = params[:queue_name]
    if queue_url
    _, _, _, aws_account, queue_name = queue_url.split('/')
    aws_account = parts[-2]
    queue_name = parts[-1]
    span.set_tag(Ext::TAG_AWS_ACCOUNT, aws_account)
    end
    span.set_tag(Ext::TAG_QUEUE_NAME, queue_name)
end
