require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/contrib/active_record/ext'
require 'ddtrace/contrib/active_record/utils'

module Datadog
  module Contrib
    module ActiveRecord
      module Configuration
        # Custom settings for the ActiveRecord integration
        class Settings < Contrib::Configuration::Settings
          option  :analytics_enabled,
                  default: -> { env_to_bool(Ext::ENV_ANALYTICS_ENABLED, false) },
                  lazy: true

          option  :analytics_sample_rate,
                  default: -> { env_to_float(Ext::ENV_ANALYTICS_SAMPLE_RATE, 1.0) },
                  lazy: true

          option :orm_service_name
          option :service_name, depends_on: [:tracer] do |value|
            (value || Utils.adapter_name).tap do |service_name|
              tracer.set_service_info(service_name, Ext::APP, Datadog::Ext::AppTypes::DB)
            end
          end

          option :tracer, default: Datadog.tracer do |value|
            value.tap do
              Events.subscriptions.each do |subscription|
                subscription.tracer = value
              end
            end
          end
        end
      end
    end
  end
end
