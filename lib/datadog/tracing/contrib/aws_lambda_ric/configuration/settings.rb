# frozen_string_literal: true

require_relative "../../configuration/settings"

module Datadog
  module Tracing
    module Contrib
      module AwsLambdaRic
        module Configuration
          # Configuration for AWS Lambda RIC instrumentation.
          # @public_api
          class Settings < Contrib::Configuration::Settings
            option :on_error do |o|
              o.type :proc, nilable: true
            end
          end
        end
      end
    end
  end
end
