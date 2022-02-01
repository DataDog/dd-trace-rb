# typed: false
require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/contrib/mongodb/ext'

module Datadog
  module Contrib
    module MongoDB
      module Configuration
        # Custom settings for the MongoDB integration
        # @public_api
        class Settings < Contrib::Configuration::Settings
          DEFAULT_QUANTIZE = { show: [:collection, :database, :operation] }.freeze

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

          option :quantize, default: DEFAULT_QUANTIZE
          option :service_name, default: Ext::DEFAULT_PEER_SERVICE_NAME
        end
      end
    end
  end
end
