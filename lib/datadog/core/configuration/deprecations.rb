# frozen_string_literal: true

require_relative 'supported_configurations'
require_relative '../logger'
require_relative '../utils/only_once'

module Datadog
  module Core
    module Configuration
      module Deprecations
        LOG_DEPRECATIONS_ONLY_ONCE = Datadog::Core::Utils::OnlyOnce.new

        def self.log_deprecations_from_all_sources(logger, deprecations: DEPRECATIONS, alias_to_canonical: ALIAS_TO_CANONICAL)
          LOG_DEPRECATIONS_ONLY_ONCE.run do
            log_deprecated_environment_variables(logger, ENV, 'environment', deprecations, alias_to_canonical)
            customer_config = StableConfig.configuration.dig(:local, :config)
            log_deprecated_environment_variables(logger, customer_config, 'local', deprecations, alias_to_canonical) if customer_config
            fleet_config = StableConfig.configuration.dig(:fleet, :config)
            log_deprecated_environment_variables(logger, fleet_config, 'fleet', deprecations, alias_to_canonical) if fleet_config
          end
        end

        private_class_method def self.log_deprecated_environment_variables(logger, source_env, source_name, deprecations, alias_to_canonical)
          deprecations.each do |deprecated_env_var, message|
            next unless source_env.key?(deprecated_env_var)

            Datadog::Core.log_deprecation(disallowed_next_major: false, logger: logger) do
              "#{deprecated_env_var} #{source_name} variable is deprecated" +
                (alias_to_canonical[deprecated_env_var] ? ", use #{alias_to_canonical[deprecated_env_var]} instead." : ". #{message}.")
            end
          end
        end
      end
    end
  end
end
