require 'ddtrace/contrib/action_mailer/ext'
require 'ddtrace/contrib/action_mailer/event'

module Datadog
  module Contrib
    module ActionMailer
      module Events
        # Defines instrumentation for process.action_mailer event
        module Process
          include ActionMailer::Event

          EVENT_NAME = 'process.action_mailer'.freeze

          module_function

          def event_name
            self::EVENT_NAME
          end

          def span_name
            Ext::SPAN_PROCESS
          end

          def span_type
            # process.action_mailer processes email and renders partial templates
            Datadog::Ext::HTTP::TEMPLATE
          end

          def process(span, event, _id, payload)
            super

            span.span_type = span_type
            span.set_tag(Ext::TAG_ACTION, payload[:action])
            span.set_tag(Ext::TAG_MAILER, payload[:mailer])
          end
        end
      end
    end
  end
end
