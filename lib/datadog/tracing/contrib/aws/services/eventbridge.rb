# frozen_string_literal: true

require_relative '../ext'

def add_eventbridge_tags(span, params)
  rule_name = params[:name] || params[:rule]
  span.set_tag(Datadog::Tracing::Contrib::Aws::Ext::TAG_RULE_NAME, rule_name)
end
