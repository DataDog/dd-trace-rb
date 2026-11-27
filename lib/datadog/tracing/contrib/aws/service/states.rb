# frozen_string_literal: true

require_relative "base"
require_relative "../arn"
require_relative "../ext"

module Datadog
  module Tracing
    module Contrib
      module Aws
        module Service
          # States tag handlers.
          class States < Base
            SERVICE = "states"

            # A version or alias ARN appends `:<qualifier>` to the state machine.
            # @see https://docs.aws.amazon.com/service-authorization/latest/reference/list_awsstepfunctions.html
            STATE_MACHINE_RESOURCE_FORMAT = %r{\AstateMachine:(?<name>[^:/]+)(?::[^:/]+)?\z}

            # A Distributed Map child execution adds `/<map run label>` to the
            # state machine name, and an Express execution ends in its own id.
            EXECUTION_RESOURCE_FORMAT = %r{
              \A(?:
                execution:(?<name>[^:/]+)(?:/[^:/]+)?:[^:/]+ |
                express:(?<name>[^:/]+)(?:/[^:/]+)?:[^:/]+:[^:/]+
              )\z
            }x

            def add_tags(span, params)
              execution_arn = params[:execution_arn]
              state_machine_arn = params[:state_machine_arn]

              # `name` is the execution name on `StartExecution`, so only an ARN-less request reads it.
              if execution_arn.nil? && state_machine_arn.nil?
                span.set_tag(Aws::Ext::TAG_STATE_MACHINE_NAME, params[:name])
                return
              end

              state_machine_name, account_id = parse_state_machine(execution_arn, state_machine_arn)
              return unless state_machine_name

              span.set_tag(Aws::Ext::TAG_EXECUTION_ARN, execution_arn) if execution_arn
              span.set_tag(Aws::Ext::TAG_STATE_MACHINE_ARN, state_machine_arn) if state_machine_arn
              span.set_tag(Aws::Ext::TAG_AWS_ACCOUNT, account_id) if account_id
              span.set_tag(Aws::Ext::TAG_STATE_MACHINE_NAME, state_machine_name)
            end

            private

            def parse_state_machine(execution_arn, state_machine_arn)
              execution = Aws::Arn.parse(execution_arn)
              execution_name = execution&.resource_name(SERVICE, EXECUTION_RESOURCE_FORMAT)
              return if execution_arn && execution_name.nil?

              state_machine = Aws::Arn.parse(state_machine_arn)
              state_machine_name = state_machine&.resource_name(SERVICE, STATE_MACHINE_RESOURCE_FORMAT)
              return if state_machine_arn && state_machine_name.nil?

              # Two ARNs that name different state machines resolve to nothing.
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
