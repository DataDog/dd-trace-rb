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
            # deliver.action_mailer sends emails
            Datadog::Ext::AppTypes::Worker
          end

          def process(span, event, _id, payload)
            super

            span.span_type = span_type
            span.set_tag(Ext::TAG_MAILER, payload[:mailer])
            span.set_tag(Ext::TAG_MSG_ID, payload[:message_id])
          end
        end
      end
    end
  end
end
