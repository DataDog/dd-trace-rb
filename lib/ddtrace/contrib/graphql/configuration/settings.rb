require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/ext/app_types'
require 'ddtrace/contrib/graphql/ext'

module Datadog
  module Contrib
    module GraphQL
      module Configuration
        # Custom settings for the GraphQL integration
        class Settings < Contrib::Configuration::Settings
          option  :analytics_enabled,
                  default: -> { env_to_bool(Ext::ENV_ANALYTICS_ENABLED, nil) },
                  lazy: true

          option  :analytics_sample_rate,
                  default: -> { env_to_float(Ext::ENV_ANALYTICS_SAMPLE_RATE, 1.0) },
                  lazy: true

          option :schemas
          option :service_name, default: Ext::SERVICE_NAME
        end
      end
    end
  end
end
