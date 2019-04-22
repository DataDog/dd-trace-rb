require 'ddtrace/contrib/action_mailer/ext'
require 'ddtrace/contrib/action_mailer/event'

 module Datadog
  module Contrib
    module ActionMailer
      module Events
        # Defines instrumentation for process.action_mailer event
        module Process
          include ActionMailer::Event

           EVENT_NAME = 'process.action_cable'.freeze

           module_function

           def event_name
            self::EVENT_NAME
          end

           def span_name
            Ext::SPAN_PROCESS
          end
        end
      end
    end
  end
end