# frozen_string_literal: true

require_relative './base'
require_relative '../ext'

module Datadog
  module Tracing
    module Contrib
      module Aws
        module Service
          # States tag handlers.
          class States < Base
            def add_tags(span, params)
              state_machine_name = params[:name]
              state_machine_arn = params[:state_machine_arn]
              execution_arn = params[:execution_arn]
              state_machine_account_id = nil

              if state_machine_arn
                span.set_tag(Aws::Ext::TAG_STATE_MACHINE_ARN, state_machine_arn)
                # https://docs.aws.amazon.com/step-functions/latest/apireference/API_StartExecution.html#API_StartExecution_RequestSyntax:~:text=Required%3A%20No-,stateMachineArn,-The%20Amazon%20Resource
                # arn:<partition>:states:<region>:<account-id>:stateMachine:<myStateMachineName>
                # arn:<partition>:states:<region>:<account-id>:stateMachine:<myStateMachineName>:10
                # arn:<partition>:states:<region>:<account-id>:stateMachine:<myStateMachineName:PROD>
                # There are 3 patterns to cover and attempt to capture the `myStateMachineName`, it should always be in index 6 and account_id at index 4
                parts = state_machine_arn.split(':')
                if state_machine_name == nil
                  state_machine_name ||= parts[6]
                end
                state_machine_account_id = parts[4]
              elsif execution_arn
                span.set_tag(Aws::Ext::TAG_STATE_EXECUTION_ARN, execution_arn)
                # express
                # arn:aws:states:sa-east-1:123456789012:express:targetStateMachineName:1234:5678
                # standard
                # arn:aws:states:sa-east-1:123456789012:execution:targetStateMachineName:1234
                parts = execution_arn.split(':')
                if state_machine_name == nil
                  state_machine_name ||= parts[6]
                end
                state_machine_account_id = parts[4]
              end
              
              if state_machine_account_id
                span.set_tag(Aws::Ext::TAG_AWS_ACCOUNT, state_machine_account_id)
              end
              if state_machine_name
                span.set_tag(Aws::Ext::TAG_STATE_MACHINE_NAME, state_machine_name)
              end
            end
          end
        end
      end
    end
  end
end
