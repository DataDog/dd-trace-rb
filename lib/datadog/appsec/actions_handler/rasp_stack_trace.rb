# frozen_string_literal: true

module Datadog
  module AppSec
    module ActionsHandler
      # Object that holds a metastruct, and modify the exploit group stack traces
      class RaspStackTrace
        def initialize(metastruct)
          @metastruct = metastruct
        end

        def count
          @metastruct&.dig(AppSec::Ext::TAG_STACK_TRACE, AppSec::Ext::EXPLOIT_PREVENTION_EVENT_CATEGORY)&.size || 0
        end

        def push(stack_trace)
          return if @metastruct.nil?

          # steep:ignore:start
          @metastruct[AppSec::Ext::TAG_STACK_TRACE] ||= {}
          @metastruct[AppSec::Ext::TAG_STACK_TRACE][AppSec::Ext::EXPLOIT_PREVENTION_EVENT_CATEGORY] ||= []
          @metastruct[AppSec::Ext::TAG_STACK_TRACE][AppSec::Ext::EXPLOIT_PREVENTION_EVENT_CATEGORY] << stack_trace
          # steep:ignore:end
        end
      end
    end
  end
end
