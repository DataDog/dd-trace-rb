require_relative '../../configuration/settings'
require_relative '../ext'

require_relative '../../propagation/sql_comment'

module Datadog
  module Tracing
    module Contrib
      module Mysql2
        module Configuration
          # Custom settings for the Mysql2 integration
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

            option :service_name do |o|
              o.default { ENV.fetch(Ext::ENV_SERVICE_NAME, Ext::DEFAULT_PEER_SERVICE_NAME) }
              o.lazy
            end

            option :comment_propagation do |o|
              o.default do
                ENV.fetch(
                  Contrib::Propagation::SqlComment::Ext::ENV_DBM_PROPAGATION_MODE,
                  Contrib::Propagation::SqlComment::Ext::DISABLED
                )
              end
              o.lazy
            end
          end
        end
      end
    end
  end
end
