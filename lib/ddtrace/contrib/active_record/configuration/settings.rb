require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/contrib/active_record/ext'
require 'ddtrace/contrib/active_record/utils'

module Datadog
  module Contrib
    module ActiveRecord
      module Configuration
        # Custom settings for the ActiveRecord integration
        class Settings < Contrib::Configuration::Settings
          option :analytics_enabled do |o|
            o.default { env_to_bool(Ext::ENV_ANALYTICS_ENABLED, false) }
            o.lazy
          end

          option :analytics_sample_rate do |o|
            o.default { env_to_float(Ext::ENV_ANALYTICS_SAMPLE_RATE, 1.0) }
            o.lazy
          end

          option :orm_service_name
          option :service_name do |o|
            o.default { Utils.adapter_name }
            o.lazy
          end
        end
      end
    end
  end
end
