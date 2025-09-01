# frozen_string_literal: true

require_relative 'supported_configurations'
require_relative '../logger'

module Datadog
  module Core
    module Configuration
      class ConfigHelper
        def initialize(
          env_vars: ENV,
          source: 'environment',
          supported_configurations: SUPPORTED_CONFIGURATIONS,
          aliases: ALIASES,
          alias_to_canonical: ALIAS_TO_CANONICAL,
          raise_on_unknown_env_var: false
        )
          @env_vars = env_vars
          @source = source
          @supported_configurations = supported_configurations
          @aliases = aliases
          @alias_to_canonical = alias_to_canonical
          @raise_on_unknown_env_var = raise_on_unknown_env_var
        end

        def [](name)
          get_environment_variable(name)
        end

        def fetch(name, default_value = UNSET)
          if (item = get_environment_variable(name))
            return item
          end

          return yield(name) if block_given?
          return default_value unless default_value == UNSET

          raise KeyError, "key not found: #{name}"
        end

        def key?(name)
          !get_environment_variable(name).nil?
        end

        alias_method :has_key?, :key?
        alias_method :include?, :key?
        alias_method :member?, :key?

        # Returns the environment variable, if it's supported or a non Datadog
        # configuration. Otherwise, it raises an error.
        #
        # @param name [String] Environment variable name
        # @param default_value [String, nil] Default value to return if the environment variable is not set
        # @param env_vars [Hash[String, String]] Environment variables to use
        # @return [String, nil] The environment variable value
        # @raise [RuntimeError] if the configuration is not supported
        def get_environment_variable(name, default_value = nil, env_vars: @env_vars)
          # datadog-ci-rb is using dd-trace-rb config DSL, which uses this method.
          # Until we've correctly implemented support for datadog-ci-rb, we disable config inversion if ci is enabled.
          if !defined?(::Datadog::CI) &&
              (name.start_with?('DD_', 'OTEL_') || @alias_to_canonical[name]) &&
              !@supported_configurations[name]
            if defined?(@raise_on_unknown_env_var) && @raise_on_unknown_env_var # Only enabled for tests!
              if @alias_to_canonical[name]
                raise "Please use #{@alias_to_canonical[name]} instead of #{name}. See docs/AccessEnvironmentVariables.md for details."
              else
                raise "Missing #{name} env/configuration in \"supported-configurations.json\" file. See docs/AccessEnvironmentVariables.md for details."
              end
            end
            # TODO: Send telemetry to know if we ever miss an env var
            return nil
          end

          config = env_vars[name]
          if config.nil? && @aliases[name]
            @aliases[name].each do |alias_name|
              return env_vars[alias_name] if env_vars[alias_name]
            end
          end

          config || default_value
        end

        # Anchor object that represents an undefined default value.
        # This is necessary because `nil` is a valid default value.
        UNSET = Object.new
        private_constant :UNSET
      end
    end
  end
end
