# frozen_string_literal: true

require_relative 'stack_trace/representor'
require_relative 'stack_trace/collector'

require_relative '../../tracing/metadata/metastruct'

module Datadog
  module AppSec
    module ActionsHandler
      # Adds stack traces to meta_struct
      module StackTrace
        module_function

        def skip_stack_trace?(context, group:)
          if context.trace.nil? && context.span.nil?
            Datadog.logger.debug { 'Cannot find trace or service entry span to add stack trace' }
            return true
          end

          max_collect = Datadog.configuration.appsec.stack_trace.max_collect
          return false if max_collect == 0

          stack_traces_count = 0

          unless context.trace.nil?
            trace_dd_stack = context.trace.metastruct[AppSec::Ext::TAG_STACK_TRACE]
            stack_traces_count += trace_dd_stack[group].size unless trace_dd_stack.nil? || trace_dd_stack[group].nil?
          end

          unless context.span.nil?
            span_dd_stack = context.span.metastruct[AppSec::Ext::TAG_STACK_TRACE]
            stack_traces_count += span_dd_stack[group].size unless span_dd_stack.nil? || span_dd_stack[group].nil?
          end

          stack_traces_count >= max_collect
        end

        def collect_stack_frames
          # caller_locations without params always returns an array but steep still thinks it can be nil
          # So we add || [] but it will never run the second part anyway (either this or steep:ignore)
          stack_frames = caller_locations || []
          # Steep thinks that path can still be nil and that include? is not a method of nil
          # We must add a variable assignment to avoid this
          stack_frames.reject! do |loc|
            path = loc.path
            next true if path.nil?

            path.include?('lib/datadog')
          end

          StackTrace::Collector.collect(stack_frames)
        end

        def add_stack_trace_to_context(stack_trace, context, group:)
          # We use methods defined in Tracing::Metadata::Tagging,
          # which means we can use both the trace and the service entry span
          service_entry_op = (context.trace || context.span)

          dd_stack = service_entry_op.metastruct[AppSec::Ext::TAG_STACK_TRACE]
          if dd_stack.nil?
            service_entry_op.metastruct[AppSec::Ext::TAG_STACK_TRACE] = {}
            dd_stack = service_entry_op.metastruct[AppSec::Ext::TAG_STACK_TRACE]
          end

          dd_stack[AppSec::Ext::EXPLOIT_PREVENTION_EVENT_CATEGORY] ||= []
          stack_group = dd_stack[AppSec::Ext::EXPLOIT_PREVENTION_EVENT_CATEGORY]

          stack_group << stack_trace
        rescue StandardError => e
          Datadog.logger.debug("Unable to add stack_trace #{stack_trace.id} in metastruct, ignoring it. Caused by: #{e}")
        end
      end
    end
  end
end
