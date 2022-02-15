module Datadog
  module AppSec
    module Contrib
      module Rails
        # Rails specific framework tie
        module Framework
          def self.setup
            Datadog::AppSec.configure do |datadog_config|
              rails_config = config_with_defaults(datadog_config)
              activate_rack!(datadog_config, rails_config)
            end
          end

          def self.config_with_defaults(datadog_config)
            datadog_config[:rails]
          end

          # Apply relevant configuration from Sinatra to Rack
          def self.activate_rack!(datadog_config, sinatra_config)
            datadog_config.instrument(
              :rack,
            )
          end
        end
      end
    end
  end
end
