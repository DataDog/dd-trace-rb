# frozen_string_literal: true

require_relative '../../configuration/settings'
require_relative '../ext'

module Datadog
  module Tracing
    module Contrib
      module AwsLambdaRic
        module Configuration
          # Custom settings for the AWS Lambda RIC integration
          class Settings < Contrib::Configuration::Settings
            option :enabled, default: true
            option :analytics_enabled, default: false
            option :analytics_sample_rate, default: 1.0
            option :service_name, default: Ext::TAG_DEFAULT_AGENT
            option :peer_service, default: nil
            option :on_error, default: nil
          end
        end
      end
    end
  end
end
