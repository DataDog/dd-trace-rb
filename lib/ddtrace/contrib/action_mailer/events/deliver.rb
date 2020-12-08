require 'ddtrace/contrib/action_mailer/ext'
require 'ddtrace/contrib/action_mailer/event'

module Datadog
  module Contrib
    module ActionMailer
      module Events
        # Defines instrumentation for process.action_mailer event
        module Deliver
          include ActionMailer::Event

          EVENT_NAME = 'deliver.action_mailer'.freeze

          module_function

          def event_name
            self::EVENT_NAME
          end

          def span_name
            Ext::SPAN_DELIVER
          end

          def span_type
            # ActionMailer creates emails like a controller
            Datadog::Ext::AppTypes::Worker
          end
        end
      end
    end
  end
end
