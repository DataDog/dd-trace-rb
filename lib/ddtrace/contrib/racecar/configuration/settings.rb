require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/contrib/racecar/ext'

module Datadog
  module Contrib
    module Racecar
      module Configuration
        # Custom settings for the Rack integration
        class Settings < Contrib::Configuration::Settings
          option :service_name, default: Ext::SERVICE_NAME
          option :tracer, default: Datadog.tracer do |value|
            (value || Datadog.tracer).tap do |v|
              # Make sure to update tracers of all subscriptions
              Events.subscriptions.each do |subscription|
                subscription.tracer = v
              end
            end
          end
        end
      end
    end
  end
end
