# frozen_string_literal: true

require_relative 'assets'
require_relative '../logger'
require 'json'

module Datadog
  module Core
    module Configuration
      module ConfigHelper
        # Load the supported configurations from JSON file
        SUPPORTED_CONFIG_DATA = JSON.parse(Assets.supported_configurations)
        ALIASES = SUPPORTED_CONFIG_DATA['aliases'] || {}

        def log_deprecations
          SUPPORTED_CONFIG_DATA['deprecations']&.each do |deprecation, new_value|
            if ENV[deprecation]
              Datadog::Core.log_deprecation do
                "#{deprecation} environment variable is deprecated, use #{new_value} instead."
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

        def supported_configurations
          @supported_configurations ||= begin
            # Log deprecations only once
            log_deprecations
            SUPPORTED_CONFIG_DATA['supportedConfigurations'] || {}
          end
        end

        # Returns the environment variable, if it's supported or a non Datadog
        # configuration. Otherwise, it throws an error.
        #
        # @param name [String] Environment variable name
        # @return [String, nil] The environment variable value
        # @raise [RuntimeError] if the configuration is not supported
        def get_environment_variable(name)
          if (name.start_with?('DD_', 'OTEL_') || alias_to_canonical[name]) &&
             !supported_configurations[name]
            # return nil
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
