module Datadog
  module Security
    module Contrib
      module Rails
        # Rails specific framework tie
        module Framework
          def self.setup
            Datadog::Security.configure do |datadog_config|
              rails_config = config_with_defaults(datadog_config)
              unless Datadog.configuration.instrumented_integrations.key?(:rack)
                activate_rack!(datadog_config, rails_config)
              end
            end
          end

          def self.config_with_defaults(datadog_config)
            datadog_config[:rails]
          end

          # Apply relevant configuration from Sinatra to Rack
          def self.activate_rack!(datadog_config, sinatra_config)
            datadog_config.use(
              :rack,
            )
          end
        end
      end
    end
  end
end
