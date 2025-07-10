# frozen_string_literal: true

require_relative 'assets'
require 'json'

module Datadog
  module Core
    module Configuration
      module ConfigHelper
        # Load the supported configurations from JSON file
        supported_config_data = JSON.parse(Assets.supported_configurations)
        SUPPORTED_CONFIGURATIONS = supported_config_data['supportedConfigurations'] || {}
        ALIASES = supported_config_data['aliases'] || {}
        DEPRECATIONS = supported_config_data['deprecations'] || {}

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

        def self.deprecation_messages
          # Log only during startup. We don't want to print it again when calling replace_components!
          return if @logged_deprecations
          @logged_deprecations = true

          DEPRECATIONS&.reduce([]) do |messages, (deprecation, message)|
            if ENV[deprecation]
              warning_message = "#{deprecation} environment variable is deprecated, "
              if ALIAS_TO_CANONICAL[deprecation]
                warning_message += "use #{ALIAS_TO_CANONICAL[deprecation]} instead."
              else
                warning_message += message
              end
              messages << warning_message
            end
          end
        end

        # Returns the environment variable, if it's supported or a non Datadog
        # configuration. Otherwise, it throws an error.
        #
        # @param name [String] Environment variable name
        # @return [String, nil] The environment variable value
        # @raise [RuntimeError] if the configuration is not supported
        def get_environment_variable(name)
          # List of env var that do not start with DD_ or OTEL_ but related to datadog:
          # DISABLE_DATADOG_RAILS
          if (name.start_with?('DD_', 'OTEL_') || ALIAS_TO_CANONICAL[name]) &&
            !SUPPORTED_CONFIGURATIONS[name]
            config_array = JSON.parse(File.read('tmp_config.json'))
            unless config_array.include?(name)
              config_array << name
              File.write('tmp_config.json', JSON.pretty_generate(config_array))
            end
            # return nil
            # raise "Missing #{name} env/configuration in \"supported-configurations.json\" file."
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
