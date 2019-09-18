require 'ddtrace/contrib/action_cable/ext'
require 'ddtrace/contrib/action_cable/event'

module Datadog
  module Contrib
    module ActionCable
      module Events
        # Defines instrumentation for perform_action.action_cable event
        module PerformAction
          include ActionCable::Event

          EVENT_NAME = 'perform_action.action_cable'.freeze

          module_function

          def event_name
            self::EVENT_NAME
          end

          def span_name
            Ext::SPAN_PERFORM_ACTION
          end
        end
      end
    end
  end
end
