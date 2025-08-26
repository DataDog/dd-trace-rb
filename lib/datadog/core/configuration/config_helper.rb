# frozen_string_literal: true

require_relative 'supported_configurations'
require_relative '../logger'
require 'json'

module Datadog
  module Core
    module Configuration
      module ConfigHelper
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
            if defined?(@raise_on_unknown_env_var) && @raise_on_unknown_env_var
              if ALIAS_TO_CANONICAL[name]
                raise "Please use #{ALIAS_TO_CANONICAL[name]} instead of #{name}."
              else
                raise "Missing #{name} env/configuration in \"supported-configurations.json\" file."
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

        def log_deprecated_environment_variables(env_vars: ENV, source: 'environment')
          @log_deprecations_called_with ||= {}
          return if @log_deprecations_called_with[source]

          @log_deprecations_called_with[source] = true
          # This will be executed after the logger is configured (core/components.rb:110)
          # Once for all 3 sources (ENV, local config file and fleet config file).
          # At that point we don't have access yet to the logger configuration.
          # Log level is warn for deprecations, so we don't need to set the logger level according to `DD_TRACE_DEBUG`.
          DEPRECATIONS.each do |deprecation, message|
            next unless env_vars.key?(deprecation)

            # As we only use warn level, we can use a new logger.
            # Using logger_without_configuration is not possible as it uses an environment variable.
            Datadog::Core.log_deprecation(disallowed_next_major: false) do
              "#{deprecation} #{source} variable is deprecated" +
                (ALIAS_TO_CANONICAL[deprecation] ? ", use #{ALIAS_TO_CANONICAL[deprecation]} instead." : ". #{message}.")
            end
          end
        end
      end
    end
  end
end
