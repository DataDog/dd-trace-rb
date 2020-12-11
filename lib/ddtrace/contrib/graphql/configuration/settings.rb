require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/ext/app_types'
require 'ddtrace/contrib/graphql/ext'

module Datadog
  module Contrib
    module GraphQL
      module Configuration
        # Custom settings for the GraphQL integration
        class Settings < Contrib::Configuration::Settings
          option :enabled do |o|
            o.default { env_to_bool(Ext::ENV_ENABLED, true) }
            o.lazy
          end

          option :analytics_enabled do |o|
            o.default { env_to_bool([Ext::ENV_ANALYTICS_ENABLED, Ext::ENV_ANALYTICS_ENABLED_OLD], nil) }
            o.lazy
          end

          option :analytics_sample_rate do |o|
            o.default { env_to_float([Ext::ENV_ANALYTICS_SAMPLE_RATE, Ext::ENV_ANALYTICS_SAMPLE_RATE_OLD], 1.0) }
            o.lazy
          end

          option :schemas
          option :service_name, default: Ext::SERVICE_NAME
        end
      end
    end
  end
end
