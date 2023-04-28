# frozen_string_literal: true

require_relative '../ext'

def add_states_tags(span, params)
  state_machine_name = params[:name]
  state_machine_arn = params[:state_machine_arn]
  execution_arn = params[:execution_arn]
  state_machine_account_id = ''

  if execution_arn
    # 'arn:aws:states:us-east-1:123456789012:execution:example-state-machine:example-execution'
    parts = execution_arn.split(':')
    state_machine_name = parts[-2]
    state_machine_account_id = parts[4]

  end

  if state_machine_arn
    # example statemachinearn: arn:aws:states:us-east-1:123456789012:stateMachine:MyStateMachine
    parts = state_machine_arn.split(':')
    state_machine_name ||= parts[-1]
    state_machine_account_id = parts[-3]
  end
  span.set_tag(Datadog::Tracing::Contrib::Aws::Ext::TAG_AWS_ACCOUNT, state_machine_account_id)
  span.set_tag(Datadog::Tracing::Contrib::Aws::Ext::TAG_STATE_MACHINE_NAME, state_machine_name)
end
