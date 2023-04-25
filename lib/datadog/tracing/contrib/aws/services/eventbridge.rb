def add_eventbridge_tags(span, params)
    rule_name = params[:name] || params[:rule]
    span.set_tag(Ext::TAG_RULE_NAME, rule_name)
end