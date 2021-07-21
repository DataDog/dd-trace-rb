require 'datadog/security/contrib/configuration/settings'
require 'datadog/security/contrib/rack/ext'

module Datadog
  module Security
    module Contrib
      module Rack
        module Configuration
          # Custom settings for the Rack integration
          class Settings < Datadog::Security::Contrib::Configuration::Settings
            option :enabled do |o|
              o.default { env_to_bool(Ext::ENV_ENABLED, true) }
              o.lazy
            end
          end
        end
      end
    end
  end
end
