# frozen_string_literal: true

require_relative 'assets/supported_configurations'
require_relative '../logger'
require 'json'

module Datadog
  module Core
    module Configuration
      module ConfigHelper
        # Load the supported configurations from JSON file. We will do this AOT.
        SUPPORTED_CONFIGURATIONS = Assets::SUPPORTED_CONFIG_DATA[:supportedConfigurations] || {}
        private_constant :SUPPORTED_CONFIGURATIONS

        ALIASES = Assets::SUPPORTED_CONFIG_DATA[:aliases] || {}
        private_constant :ALIASES

        # Returns the environment variable, if it's supported or a non Datadog
        # configuration. Otherwise, it throws an error.
        #
        # @param name [String] Environment variable name
        # @return [String, nil] The environment variable value
        # @raise [RuntimeError] if the configuration is not supported
        def get_environment_variable(name, env_vars: ENV, source: 'environment')
          # If we have a deprecated env var that does not start with DD_ or OTEL_, without an alias,
          # it will not do the third check (SUPPORTED_CONFIGURATIONS[name]) and will not call log_deprecations.
          log_deprecations(env_vars, source)

          # datadog-ci-rb is using dd-trace-rb config DSL, which uses this method.
          # Until we've correctly implemented support for datadog-ci-rb, we disable config inversion if ci is enabled.
          if !defined?(::Datadog::CI) &&
             (name.start_with?('DD_', 'OTEL_') || alias_to_canonical[name]) &&
             !SUPPORTED_CONFIGURATIONS[name]
            if defined?(@dd_test_environment) && @dd_test_environment
              raise "Missing #{name} env/configuration in \"supported-configurations.json\" file."
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

          config
        end

        private

        # An env can be deprecated without a replacement (e.g.: if we remove a feature)
        def log_deprecations(env_vars, source)
          @log_deprecations_called ||= {}
          return if @log_deprecations_called[source]

          @log_deprecations_called[source] = true
          @temp_logger ||= Core::Logger.new($stdout)
          Assets::SUPPORTED_CONFIG_DATA[:deprecations]&.each do |deprecation, message|
            next unless env_vars[deprecation]

            # As we only use warn level, we can use a new logger.
            # Using logger_without_configuration is not possible as it uses an environment variable.
            Datadog::Core.log_deprecation(logger: @temp_logger) do
              value = "#{deprecation} #{source} variable is deprecated"
              value += ", use #{alias_to_canonical[deprecation]} instead" if alias_to_canonical[deprecation]
              value += '.'
              value += " #{message}." unless message.nil? || message.empty?
              value
            end
          end
        end

        def alias_to_canonical
          @alias_to_canonical ||= begin
            ALIASES.reduce({}) do |alias_to_canonical, (canonical, alias_list)|
              alias_list.each do |alias_name|
                if alias_to_canonical[alias_name]
                  raise "The alias #{alias_name} is already used for #{alias_to_canonical[alias_name]}."
                end
                alias_to_canonical[alias_name] = canonical
              end
              alias_to_canonical
            end
          end
        end

        # This should never be used outside of datadog test environment.
        def dd_test_environment!
          @dd_test_environment = true
        end
      end
    end
  end
end
