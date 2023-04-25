def add_states_tags(span, params)
    state_machine_name = params[:name]
    state_machine_arn = params[:state_machine_arn]
    execution_arn = params[:execution_arn]

    if execution_arn
      # 'arn:aws:states:us-east-1:123456789012:execution:example-state-machine:example-execution'
      state_machine_name = execution_arn.split(':')[-2]
    end

    if state_machine_arn
      # example statemachinearn: arn:aws:states:us-east-1:123456789012:stateMachine:MyStateMachine
      parts = state_machine_arn.split(':')
      state_machine_name = parts[-1]
      state_machine_account_id = parts[-3]
    end
    span.set_tag(Ext::TAG_AWS_ACCOUNT, state_machine_account_id)
    # state_machine_name = create_state_machine_name || start_execution_state_machine_name
    span.set_tag(Ext::TAG_STATE_MACHINE_NAME, state_machine_name)
end