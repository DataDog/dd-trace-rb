def add_dynamodb_tags(span, params)
    table_name = params[:table_name]
    span.set_tag(Ext::TAG_TABLE_NAME, table_name)
end