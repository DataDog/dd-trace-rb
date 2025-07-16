# frozen_string_literal: true

require_relative 'assets'
require_relative '../logger'
require 'json'

module Datadog
  module Core
    module Configuration
      module ConfigHelper
        # Load the supported configurations from JSON file. We will do this AOT.
        SUPPORTED_CONFIG_DATA = JSON.parse(Assets.supported_configurations)
        private_constant :SUPPORTED_CONFIG_DATA

        SUPPORTED_CONFIGURATIONS = SUPPORTED_CONFIG_DATA['supportedConfigurations'] || {}
        private_constant :SUPPORTED_CONFIGURATIONS

        ALIASES = SUPPORTED_CONFIG_DATA['aliases'] || {}
        private_constant :ALIASES

        # Returns the environment variable, if it's supported or a non Datadog
        # configuration. Otherwise, it throws an error.
        #
        # @param name [String] Environment variable name
        # @return [String, nil] The environment variable value
        # @raise [RuntimeError] if the configuration is not supported
        def get_environment_variable(name)
          # If we have a deprecated env var that does not start with DD_ or OTEL_, without an alias,
          # it will not do the third check (SUPPORTED_CONFIGURATIONS[name]) and will not call log_deprecations.
          log_deprecations unless @log_deprecations_called

          # datadog-ci-rb is using dd-trace-rb config DSL, which uses this method.
          # Until we've correctly implemented support for datadog-ci-rb, we disable config inversion if ci is enabled.
          if !defined?(::Datadog::CI) &&
             (name.start_with?('DD_', 'OTEL_') || alias_to_canonical[name]) &&
             !SUPPORTED_CONFIGURATIONS[name]
            # return nil
            raise "Missing #{name} env/configuration in \"supported-configurations.json\" file."
          end

          config = ENV[name]
          if config.nil? && ALIASES[name]
            ALIASES[name].each do |alias_name|
              return ENV[alias_name] if ENV[alias_name]
            end
          end

          config
        end

        private

        # An env can be deprecated without a replacement (e.g.: if we remove a feature)
        def log_deprecations
          @log_deprecations_called = true
          SUPPORTED_CONFIG_DATA['deprecations']&.each do |deprecation, message|
            if ENV[deprecation]
              # As we only use warn level, we can use a new logger.
              # Using logger_without_configuration is not possible as it uses an environment variable.
              Datadog::Core.log_deprecation(logger: Core::Logger.new($stdout)) do
                value = "#{deprecation} environment variable is deprecated"
                value += ", use #{alias_to_canonical[deprecation]} instead" if alias_to_canonical[deprecation]
                value += '.'
                value += " #{message}." unless message.nil? || message.empty?
                value
              end
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
      end
    end
  end
end
