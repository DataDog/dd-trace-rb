# frozen_string_literal: true

require_relative 'actions_handler/stack_trace_in_metastruct'
require_relative 'actions_handler/stack_trace_collection'

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

        context = AppSec.active_context
        if context.nil? || context.trace.nil? && context.span.nil?
          Datadog.logger.debug { 'Cannot find trace or service entry span to add stack trace' }
          return
        end

        config = Datadog.configuration.appsec.stack_trace

        # Check that the sum of stack_trace count in trace and entry_span does not exceed configuration
        span_stack = ActionsHandler::StackTraceInMetastruct.create(context.span&.metastruct)
        trace_stack = ActionsHandler::StackTraceInMetastruct.create(context.trace&.metastruct)
        return if config.max_collect != 0 && span_stack.count + trace_stack.count >= config.max_collect

        # Generate stacktrace
        utf8_stack_id = action_params['stack_id'].encode('UTF-8') if action_params['stack_id']
        stack_frames = ActionsHandler::StackTraceCollection.collect(
          max_depth: config.max_depth,
          top_percent: config.max_depth_top_percent
        )

        # Add newly created stacktrace to metastruct
        stack = context.trace.nil? ? span_stack : trace_stack
        stack.push({ language: 'ruby', id: utf8_stack_id, frames: stack_frames })
      end

      def generate_schema(_action_params); end
    end
  end
end
