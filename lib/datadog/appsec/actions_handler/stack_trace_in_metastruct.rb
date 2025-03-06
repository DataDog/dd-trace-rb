# frozen_string_literal: true

module Datadog
  module AppSec
    module ActionsHandler
      # Object that holds a metastruct, and modify the exploit group stack traces
      class StackTraceInMetastruct
        # Implementation with empty metastruct
        class Noop
          def count
            0
          end

          def push(_)
            nil
          end
        end

        def self.create(metastruct)
          metastruct.nil? ? Noop.new : new(metastruct)
        end

        def initialize(metastruct)
          @metastruct = metastruct
        end

        def count
          @metastruct.dig(AppSec::Ext::TAG_STACK_TRACE, AppSec::Ext::EXPLOIT_PREVENTION_EVENT_CATEGORY)&.size || 0
        end

        def push(stack_trace)
          @metastruct[AppSec::Ext::TAG_STACK_TRACE] ||= {}
          @metastruct[AppSec::Ext::TAG_STACK_TRACE][AppSec::Ext::EXPLOIT_PREVENTION_EVENT_CATEGORY] ||= []
          @metastruct[AppSec::Ext::TAG_STACK_TRACE][AppSec::Ext::EXPLOIT_PREVENTION_EVENT_CATEGORY] << stack_trace
        end
      end
    end
  end
end
