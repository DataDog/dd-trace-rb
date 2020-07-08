require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/contrib/http/ext'

module Datadog
  module Contrib
    module HTTP
      module Configuration
        # Custom settings for the HTTP integration
        class Settings < Contrib::Configuration::Settings
          option :analytics_enabled do |o|
            o.default { env_to_bool(Ext::ENV_ANALYTICS_ENABLED, false) }
            o.lazy
          end

          option :analytics_sample_rate do |o|
            o.default { env_to_float(Ext::ENV_ANALYTICS_SAMPLE_RATE, 1.0) }
            o.lazy
          end

          option :distributed_tracing, default: true
          option :service_name, default: Ext::SERVICE_NAME
          option :split_by_domain, default: false
        end
      end
    end
  end
end
