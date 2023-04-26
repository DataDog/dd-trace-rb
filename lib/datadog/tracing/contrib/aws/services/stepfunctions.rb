# frozen_string_literal: true

require_relative '../ext'
require 'aws-sdk'

def add_states_tags(span, params)
  state_machine_name = params[:name]
  state_machine_arn = params[:state_machine_arn]
  execution_arn = params[:execution_arn]
  state_machine_account_id = ''

  if execution_arn
    arn = Aws::ARNParser.parse(execution_arn)
    state_machine_name = arn.resource.split(':')[-2]
    state_machine_account_id = arn.account_id
  end

  if state_machine_arn
    arn = Aws::ARNParser.parse(state_machine_arn)
    state_machine_name ||= arn.resource.split(':').last
    state_machine_account_id = arn.account_id
  end

  span.set_tag(Datadog::Tracing::Contrib::Aws::Ext::TAG_AWS_ACCOUNT, state_machine_account_id)
  span.set_tag(Datadog::Tracing::Contrib::Aws::Ext::TAG_STATE_MACHINE_NAME, state_machine_name)
end
