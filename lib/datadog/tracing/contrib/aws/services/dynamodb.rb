# frozen_string_literal: true

require_relative '../ext'

def add_dynamodb_tags(span, params)
  table_name = params[:table_name]
  span.set_tag(Datadog::Tracing::Contrib::Aws::Ext::TAG_TABLE_NAME, table_name)
end
