def add_s3_tags(span, params)
    bucket_name = params[:bucket]
    span.set_tag(Ext::TAG_BUCKET_NAME, bucket_name)
end