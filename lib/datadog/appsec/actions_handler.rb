# frozen_string_literal: true

require_relative 'actions_handler/serializable_backtrace'

module Datadog
  module AppSec
    # this module encapsulates functions for handling actions that libddawf returns
    module ActionsHandler
      module_function

      def handle(actions_hash)
        # handle actions according their precedence
        # stack and schema generation should be done before we throw an interrupt signal
        generate_stack(actions_hash['generate_stack']) if actions_hash.key?('generate_stack')
        generate_schema(actions_hash['generate_schema']) if actions_hash.key?('generate_schema')
        interrupt_execution(actions_hash['redirect_request']) if actions_hash.key?('redirect_request')
        interrupt_execution(actions_hash['block_request']) if actions_hash.key?('block_request')
      end

      def interrupt_execution(action_params)
        throw(Datadog::AppSec::Ext::INTERRUPT, action_params)
      end

      def generate_stack(action_params)
        return unless Datadog.configuration.appsec.stack_trace.enabled

        # TODO: check how many stack traces we already collected

        stack_id = action_params['stack_id']
        return unless stack_id

        _backtrace = SerializableBacktrace.new(locations: caller_locations, stack_id: stack_id)

        # TODO: add stack frames to span metastruct
      end

      def generate_schema(_action_params); end
    end
  end
end
