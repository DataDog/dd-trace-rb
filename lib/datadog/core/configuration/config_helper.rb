# frozen_string_literal: true

require_relative 'assets'
require 'json'
require 'warning'

module Datadog
  module Core
    module Configuration
      module ConfigHelper
        # Load the supported configurations from JSON file
        supported_config_data = JSON.parse(Assets.supported_configurations)
        SUPPORTED_CONFIGURATIONS = supported_config_data['supportedConfigurations']
        ALIASES = supported_config_data['aliases']
        DEPRECATIONS = supported_config_data['deprecations']

        # Build alias to canonical mapping
        ALIAS_TO_CANONICAL = {}
        ALIASES&.each do |canonical, alias_list|
          alias_list.each do |alias_name|
            if ALIAS_TO_CANONICAL[alias_name]
              raise "The alias #{alias_name} is already used for #{ALIAS_TO_CANONICAL[alias_name]}."
            end
            ALIAS_TO_CANONICAL[alias_name] = canonical
          end
        end

        # Build deprecation methods
        DEPRECATION_METHODS = {}
        DEPRECATIONS&.each do |deprecation, message|
          DEPRECATION_METHODS[deprecation] = lambda do
            warning_message = "The environment variable #{deprecation} is deprecated."
            if ALIAS_TO_CANONICAL[deprecation]
              warning_message += " Please use #{ALIAS_TO_CANONICAL[deprecation]} instead."
            else
              warning_message += " #{message}"
            end
            Warning.warn("DATADOG_#{deprecation}: #{warning_message}\n")
          end
        end

        # Returns the environment variables that are supported by the tracer
        # (including all non-Datadog/OTEL specific environment variables)
        #
        # @return [Hash<String, String>] The environment variables
        def self.get_environment_variables
          configs = {}

          ENV.each do |key, value|
            if key.start_with?('DD_') || key.start_with?('OTEL_') || ALIAS_TO_CANONICAL[key]
              if SUPPORTED_CONFIGURATIONS[key]
                configs[key] = value
              elsif ALIAS_TO_CANONICAL[key] && configs[ALIAS_TO_CANONICAL[key]].nil?
                # The alias should only be used if the actual configuration is not set
                # In case that more than a single alias exist, use the one defined first in our own order
                ALIASES[ALIAS_TO_CANONICAL[key]].each do |alias_name|
                  if ENV[alias_name]
                    configs[ALIAS_TO_CANONICAL[key]] = value
                    break
                  end
                end
                # TODO(BridgeAR) Implement logging. It would have to use a timeout to
                # lazily log the message after all loading being done otherwise.
                #   debug(
                #     "Missing configuration #{env} in supported-configurations file. The environment variable is ignored."
                #   )
              end
              DEPRECATION_METHODS[key]&.call
            else
              configs[key] = value
            end
          end

          configs
        end

        def self.environment_variables
          @environment_variables ||= get_environment_variables
        end

        # Returns the environment variable, if it's supported or a non Datadog
        # configuration. Otherwise, it throws an error.
        #
        # @param name [String] Environment variable name
        # @return [String, nil] The environment variable value
        # @raise [RuntimeError] if the configuration is not supported
        def self.get_environment_variable(name)
          if (name.start_with?('DD_') || name.start_with?('OTEL_') || ALIAS_TO_CANONICAL[name]) &&
            !SUPPORTED_CONFIGURATIONS[name]
            raise "Missing #{name} env/configuration in \"supported-configurations.json\" file."
          end

          config = ENV[name]
          if config.nil? && ALIASES[name]
            ALIASES[name].each do |alias_name|
              if ENV[alias_name]
                return ENV[alias_name]
              end
            end
          end

          config
        end
      end
    end
  end
end
