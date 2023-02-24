module Datadog
  module Tracing
    module Contrib
      module ActionMailer
        # ActionMailer integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          ENV_ENABLED = 'DD_TRACE_ACTION_MAILER_ENABLED'.freeze
          ENV_ANALYTICS_ENABLED = 'DD_TRACE_ACTION_MAILER_ANALYTICS_ENABLED'.freeze
          ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_ACTION_MAILER_ANALYTICS_SAMPLE_RATE'.freeze
          SPAN_PROCESS = 'action_mailer.process'.freeze
          SPAN_DELIVER = 'action_mailer.deliver'.freeze
          TAG_COMPONENT = 'action_mailer'.freeze
          TAG_ACTION = 'action_mailer.action'.freeze
          TAG_MAILER = 'action_mailer.mailer'.freeze
          TAG_MSG_ID = 'action_mailer.message_id'.freeze
          TAG_OPERATION_DELIVER = 'deliver'.freeze
          TAG_OPERATION_PROCESS = 'process'.freeze

          TAG_SUBJECT = 'action_mailer.subject'.freeze
          TAG_TO = 'action_mailer.to'.freeze
          TAG_FROM = 'action_mailer.from'.freeze
          TAG_BCC = 'action_mailer.bcc'.freeze
          TAG_CC = 'action_mailer.cc'.freeze
          TAG_DATE = 'action_mailer.date'.freeze
          TAG_PERFORM_DELIVERIES = 'action_mailer.perform_deliveries'.freeze
        end
      end
    end
  end
end
