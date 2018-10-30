require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/contrib/mongodb/ext'

module Datadog
  module Contrib
    module MongoDB
      module Configuration
        # Custom settings for the MongoDB integration
        class Settings < Contrib::Configuration::Settings
          DEFAULT_QUANTIZE = { show: [:collection, :database, :operation] }.freeze

          option :quantize, default: DEFAULT_QUANTIZE
          option :service_name, default: Ext::SERVICE_NAME
        end
      end
    end
  end
end
