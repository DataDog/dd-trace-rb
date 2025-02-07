# frozen_string_literal: true

require_relative 'actions_handler/stack_trace'

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
        if Datadog.configuration.appsec.stack_trace.enabled
          context = AppSec::Context.active
          return if context.nil? ||
            ActionsHandler::StackTrace.skip_stack_trace?(context, group: AppSec::Ext::EXPLOIT_PREVENTION_EVENT_CATEGORY)

          collected_stack_frames = ActionsHandler::StackTrace.collect_stack_frames
          utf8_stack_id = action_params['stack_id'].encode('UTF-8') if action_params['stack_id']
          stack_trace = ActionsHandler::StackTrace::Representor.new(
            id: utf8_stack_id,
            frames: collected_stack_frames
          )

          ActionsHandler::StackTrace.add_stack_trace_to_context(
            stack_trace,
            context,
            group: AppSec::Ext::EXPLOIT_PREVENTION_EVENT_CATEGORY
          )
        end
      end

      def generate_schema(_action_params); end
    end
  end
end
