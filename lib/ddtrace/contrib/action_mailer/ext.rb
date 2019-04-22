module Datadog
  module Contrib
    module ActionMailer
      # ActionMailer integration constants
      module Ext
        APP = 'action_mailer'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_ACTION_MAILER_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_ACTION_MAILER_ANALYTICS_SAMPLE_RATE'.freeze
        SERVICE_NAME = 'action_mailer'.freeze
        SPAN_PROCESS = 'process.action_mailer'.freeze
        TAG_ACTION = 'action_mailer.action'.freeze
        TAG_MAILER = 'action_mailer.mailer'.freeze
      end
    end
  end
end
