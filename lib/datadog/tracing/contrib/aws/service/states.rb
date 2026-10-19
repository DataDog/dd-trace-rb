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

            # `arn:aws:states:us-east-1:123456789012:execution:MyStateMachine:MyExecution`,
            # or `:express:MyStateMachine:MyExecution:<uuid>` for a Synchronous
            # Express workflow. The second resource segment is the state machine
            # in both, so resolving an execution ARN yields the state machine
            # name, not the execution's.
            EXECUTION_RESOURCE_TYPES = %w[execution express].freeze

            # Both parameters, when present, describe the same state machine:
            # `state_machine_arn` names it directly and `execution_arn` names it
            # as the parent of an execution. No Step Functions operation accepts
            # both in one request today, so a disagreeing pair can only arrive
            # from a params hash this handler does not control -- a future
            # operation shape, or a caller invoking the handler directly. That
            # is reason to resolve both before tagging rather than to skip the
            # case: tagging as each is read would emit an account from one ARN
            # and a name from the other, an identity neither parameter named,
            # and the mistake would be silent.
            #
            # `name` is the state machine's own name only on an operation that
            # creates one, and such an operation carries no ARN. On
            # `StartExecution` -- the operation that supplies
            # `state_machine_arn` alongside a `name` -- `name` is the EXECUTION
            # name, so reporting it as `statemachinename` names the wrong
            # target, and `statemachinename` is a `peer.service` source. It is
            # therefore read only when the request supplied no ARN at all.
            #
            # An ARN that was supplied and did not resolve leaves the request
            # naming a target this handler cannot read. Nothing is reported in
            # that case: not the other ARN, not the account, and not `name`.
            def add_tags(span, params)
              execution_arn = params[:execution_arn]
              state_machine_arn = params[:state_machine_arn]

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

              return if execution_arn && execution.nil?
              return if state_machine_arn && state_machine.nil?

              # The two ARNs name different state machines, accounts,
              # partitions or Regions. Emitting both would publish a
              # contradiction, and picking one would be an arbitrary choice
              # between two parameters of equal authority.
              if execution && state_machine &&
                  target_identity(execution, execution_name) != target_identity(state_machine, state_machine_name)
                return
              end

              span.set_tag(Aws::Ext::TAG_AWS_EXECUTION_ARN, execution_arn) if execution
              span.set_tag(Aws::Ext::TAG_AWS_STATE_MACHINE_ARN, state_machine_arn) if state_machine

              # At least one ARN was supplied and every supplied ARN resolved,
              # so there is always an identity here. Both describe the same
              # target; the state machine ARN names it directly, so it is the
              # more specific source.
              resolved = state_machine || execution
              resolved_name = state_machine ? state_machine_name : execution_name

              account_id = resolved.account_id
              span.set_tag(Aws::Ext::TAG_AWS_ACCOUNT, account_id) if account_id
              span.set_tag(Aws::Ext::TAG_STATE_MACHINE_NAME, resolved_name)
            end

            private

            # Everything two ARNs must agree on to describe one target: the
            # state machine, the account that owns it, and the partition and
            # Region it lives in. A field one ARN omits and the other supplies
            # counts as a disagreement, because the two then describe the same
            # name with different reach.
            def target_identity(arn, name)
              [name, arn.account_id, arn.partition, arn.region]
            end
          end
        end
      end
    end
  end
end
