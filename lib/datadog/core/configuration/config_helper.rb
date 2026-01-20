# frozen_string_literal: true

require_relative 'supported_configurations'
require_relative '../logger'

module Datadog
  module Core
    module Configuration
      class ConfigHelper
        def initialize(
          source_env: ENV,
          supported_configurations: SUPPORTED_CONFIGURATION_NAMES,
          aliases: ALIASES,
          alias_to_canonical: ALIAS_TO_CANONICAL,
          raise_on_unknown_env_var: false
        )
          @source_env = source_env
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

        # This method will be used by datadog-ci-rb once it will bump its minimum dependancy of dd-trace-rb to 2.27.0.
        # In the meantime, it uses ConfigHelper#instance_variable_get(:@source_env) to set environment variables.
        def []=(name, value)
          @source_env[name] = value
        end

        # Returns the environment variable value if the environment variable is a supported Datadog configuration (starts with DD_ or OTEL_)
        # or if it is not a Datadog configuration. Otherwise, it returns nil.
        #
        # @param name [String] Environment variable name
        # @param default_value [String, nil] Default value to return if the environment variable is not set
        # @param source_env [Hash[String, String]] Environment variables to use
        # @return [String, nil] The environment variable value
        # @raise [RuntimeError] if the configuration is not supported
        def get_environment_variable(name, default_value = nil, source_env: @source_env)
          if (!defined?(::Datadog::CI) || Gem::Version.new(::Datadog::CI::VERSION::STRING) >= Gem::Version.new('1.27.0')) &&
              (name.start_with?('DD_', 'OTEL_') || @alias_to_canonical[name]) &&
              !@supported_configurations.include?(name)
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

          env_value = source_env[name]
          if env_value.nil? && @aliases[name]
            @aliases[name].each do |alias_name|
              return source_env[alias_name] if source_env[alias_name]
            end
          end

          env_value || default_value
        end

        # Only used in error message creation. Match get_environment_variable logic to return the resolved environment variable name.
        def resolve_env(name, source_env: @source_env)
          if source_env[name].nil? && @aliases[name]
            @aliases[name].each do |alias_name|
              return alias_name if source_env[alias_name]
            end
          end

          name
        end

        # Anchor object that represents an undefined default value.
        # This is necessary because `nil` is a valid default value.
        UNSET = Object.new
        private_constant :UNSET
      end
    end
  end
end
