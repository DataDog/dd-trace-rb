# frozen_string_literal: true

require_relative 'supported_configurations'
require_relative '../logger'
require 'json'

module Datadog
  module Core
    module Configuration
      class ConfigHelper
        def initialize(env_vars: ENV)
          @env_vars = env_vars
        end

        def [](name)
          self.class.get_environment_variable(name, env_vars: @env_vars)
        end

        def fetch(name, default_value = UNSET)
          if (item = self.class.get_environment_variable(name, env_vars: @env_vars))
            return item
          end

          return yield(name) if block_given?
          return default_value unless default_value == UNSET

          raise KeyError, "key not found: #{name}"
        end

        def key?(name)
          !self.class.get_environment_variable(name, env_vars: @env_vars).nil?
        end

        alias_method :has_key?, :key?
        alias_method :include?, :key?
        alias_method :member?, :key?

        # Anchor object that represents an undefined default value.
        # This is necessary because `nil` is a valid default value.
        UNSET = Object.new
        private_constant :UNSET

        class << self
          # Returns the environment variable, if it's supported or a non Datadog
          # configuration. Otherwise, it raises an error.
          #
          # @param name [String] Environment variable name
          # @param default_value [String, nil] Default value to return if the environment variable is not set
          # @param env_vars [Hash] Environment variables to use (ENV, fleet config file hash or local config file hash)
          # @param source [String] Source of the environment variables (can be 'environment' or 'local/fleet stable config)
          # @return [String, nil] The environment variable value
          # @raise [RuntimeError] if the configuration is not supported
          def get_environment_variable(name, default_value = nil, env_vars: ENV)
            # datadog-ci-rb is using dd-trace-rb config DSL, which uses this method.
            # Until we've correctly implemented support for datadog-ci-rb, we disable config inversion if ci is enabled.
            if !defined?(::Datadog::CI) &&
                (name.start_with?('DD_', 'OTEL_') || ALIAS_TO_CANONICAL[name]) &&
                !SUPPORTED_CONFIGURATIONS[name]
              if defined?(@raise_on_unknown_env_var) && @raise_on_unknown_env_var # Only enabled for tests!
                if ALIAS_TO_CANONICAL[name]
                  raise "Please use #{ALIAS_TO_CANONICAL[name]} instead of #{name}. See docs/AccessEnvironmentVariables.md for details."
                else
                  raise "Missing #{name} env/configuration in \"supported-configurations.json\" file. See docs/AccessEnvironmentVariables.md for details."
                end
              end
              # TODO: Send telemetry to know if we ever miss an env var
              return nil
            end

            config = env_vars[name]
            if config.nil? && ALIASES[name]
              ALIASES[name].each do |alias_name|
                return env_vars[alias_name] if env_vars[alias_name]
              end
            end

            config || default_value
          end

          def log_deprecated_environment_variables(logger, env_vars: ENV, source: 'environment')
            @log_deprecations_called_with ||= {}
            return if @log_deprecations_called_with[source]

            @log_deprecations_called_with[source] = true
            DEPRECATIONS.each do |deprecated_env_var, message|
              next unless env_vars.key?(deprecated_env_var)

              # As we only use warn level, we can use a new logger.
              # Using logger_without_configuration is not possible as it uses an environment variable.
              Datadog::Core.log_deprecation(disallowed_next_major: false, logger: logger) do
                "#{deprecated_env_var} #{source} variable is deprecated" +
                  (ALIAS_TO_CANONICAL[deprecated_env_var] ? ", use #{ALIAS_TO_CANONICAL[deprecated_env_var]} instead." : ". #{message}.")
              end
            end
          end

          def log_deprecations_from_all_sources(logger)
            ConfigHelper.log_deprecated_environment_variables(logger, source: 'environment')
            customer_config = StableConfig.configuration.dig(:local, :config)
            ConfigHelper.log_deprecated_environment_variables(logger, env_vars: customer_config, source: 'local') if customer_config
            fleet_config = StableConfig.configuration.dig(:fleet, :config)
            ConfigHelper.log_deprecated_environment_variables(logger, env_vars: fleet_config, source: 'fleet') if fleet_config
          end
        end
      end
    end
  end
end
