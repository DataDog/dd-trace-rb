# typed: false
require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/contrib/action_view/ext'

module Datadog
  module Contrib
    module ActionView
      module Configuration
        # Custom settings for the ActionView integration
        # @public_api
        class Settings < Contrib::Configuration::Settings
          option :enabled do |o|
            o.default { env_to_bool(Ext::ENV_ENABLED, true) }
            o.lazy
          end

          option :analytics_enabled do |o|
            o.default { env_to_bool(Ext::ENV_ANALYTICS_ENABLED, false) }
            o.lazy
          end

          option :analytics_sample_rate do |o|
            o.default { env_to_float(Ext::ENV_ANALYTICS_SAMPLE_RATE, 1.0) }
            o.lazy
          end

          option :service_name
          option :template_base_path, default: 'views/'
        end
      end
    end
  end
end
