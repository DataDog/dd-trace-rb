# frozen_string_literal: true

require_relative "base"
require_relative "../arn"
require_relative "../ext"

module Datadog
  module Tracing
    module Contrib
      module Aws
        module Service
          # States (Step Functions) tag handlers.
          class States < Base
            SERVICE = "states"

            # `arn:aws:states:us-east-1:123456789012:stateMachine:MyStateMachine`
            STATE_MACHINE_RESOURCE_TYPES = %w[stateMachine].freeze

            # The state machine is the second segment of an execution ARN
            # (`execution:MyStateMachine:MyExecution`) and of an Express
            # workflow ARN (`express:MyStateMachine:MyExecution:<uuid>`).
            EXECUTION_RESOURCE_TYPES = %w[execution express].freeze

            def add_tags(span, params)
              execution_arn = params[:execution_arn]
              state_machine_arn = params[:state_machine_arn]

              # With no ARN, `name` is the state machine's own name on a create
              # operation. On `StartExecution` it is the execution name and a
              # `peer.service` source, so it is read only when no ARN is present.
              if execution_arn.nil? && state_machine_arn.nil?
                span.set_tag(Aws::Ext::TAG_STATE_MACHINE_NAME, params[:name])
                return
              end

              state_machine_name, account_id = parse_state_machine(execution_arn, state_machine_arn)
              return unless state_machine_name

              span.set_tag(Aws::Ext::TAG_AWS_EXECUTION_ARN, execution_arn) if execution_arn
              span.set_tag(Aws::Ext::TAG_AWS_STATE_MACHINE_ARN, state_machine_arn) if state_machine_arn
              span.set_tag(Aws::Ext::TAG_AWS_ACCOUNT, account_id) if account_id
              span.set_tag(Aws::Ext::TAG_STATE_MACHINE_NAME, state_machine_name)
            end

            private

            # Returns the state machine name and account named by the given
            # ARNs, or `nil` when a supplied ARN does not resolve or the two
            # name different targets.
            def parse_state_machine(execution_arn, state_machine_arn)
              execution = Aws::Arn.parse(execution_arn)
              execution_name = execution&.typed_resource_id(SERVICE, EXECUTION_RESOURCE_TYPES)
              return if execution_arn && execution_name.nil?

              state_machine = Aws::Arn.parse(state_machine_arn)
              state_machine_name = state_machine&.typed_resource_id(SERVICE, STATE_MACHINE_RESOURCE_TYPES)
              return if state_machine_arn && state_machine_name.nil?

              # The state machine ARN names the target directly, so it is
              # preferred when both resolved. A field one ARN omits and the
              # other supplies counts as a disagreement.
              if state_machine && state_machine_name
                if execution && execution_name
                  execution_target = [execution_name, execution.account_id, execution.partition, execution.region]
                  state_machine_target = [
                    state_machine_name, state_machine.account_id, state_machine.partition, state_machine.region,
                  ]
                  return unless execution_target == state_machine_target
                end

                [state_machine_name, state_machine.account_id]
              elsif execution && execution_name
                [execution_name, execution.account_id]
              end
            end
          end
        end
      end
    end
  end
end
