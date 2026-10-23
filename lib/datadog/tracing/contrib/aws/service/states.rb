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

              execution = Aws::Arn.parse(execution_arn)
              execution_name = execution&.typed_resource_id(SERVICE, EXECUTION_RESOURCE_TYPES)
              execution = nil unless execution_name

              state_machine = Aws::Arn.parse(state_machine_arn)
              state_machine_name = state_machine&.typed_resource_id(SERVICE, STATE_MACHINE_RESOURCE_TYPES)
              state_machine = nil unless state_machine_name

              # A supplied ARN that did not resolve names a target this handler
              # cannot read, so nothing is reported.
              return if execution_arn && execution.nil?
              return if state_machine_arn && state_machine.nil?

              # Two resolved ARNs naming different targets are a contradiction;
              # emitting either would be arbitrary, so neither is.
              if execution && state_machine &&
                  target_identity(execution, execution_name) != target_identity(state_machine, state_machine_name)
                return
              end

              span.set_tag(Aws::Ext::TAG_AWS_EXECUTION_ARN, execution_arn) if execution
              span.set_tag(Aws::Ext::TAG_AWS_STATE_MACHINE_ARN, state_machine_arn) if state_machine

              # The state machine ARN names the target directly, so it is
              # preferred when both resolved.
              resolved = state_machine || execution
              resolved_name = state_machine ? state_machine_name : execution_name

              account_id = resolved.account_id
              span.set_tag(Aws::Ext::TAG_AWS_ACCOUNT, account_id) if account_id
              span.set_tag(Aws::Ext::TAG_STATE_MACHINE_NAME, resolved_name)
            end

            private

            # The fields two ARNs must share to name one target. A field one
            # omits and the other supplies counts as a disagreement.
            def target_identity(arn, name)
              [name, arn.account_id, arn.partition, arn.region]
            end
          end
        end
      end
    end
  end
end
