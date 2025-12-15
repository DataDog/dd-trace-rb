# frozen_string_literal: true

require 'spec_helper'
require 'json'

RSpec.describe 'Supported configurations' do
  describe 'consistency validation' do
    it 'validates that the generated data matches the JSON file' do
      json_data = JSON.parse(File.read('supported-configurations.json')).transform_keys(&:to_sym)
      aliases = {}
      deprecations = Set.new
      alias_to_canonical = {}
      supported_configurations = json_data[:supportedConfigurations].each.with_object(Set.new) do |(name, configs), result|
        configs.each do |config|
          config["aliases"]&.each do |alias_name|
            aliases[name] ||= []
            aliases[name] << alias_name
            alias_to_canonical[alias_name] = name

            # If an alias is not registered as its own config, it is by default deprecated
            deprecations << alias_name unless json_data.dig(:supportedConfigurations, alias_name)
          end
          # Add deprecated configs with no replacement provided
          deprecations << name if config["deprecations"]
        end
        result << name
      end

      error_message = <<~ERROR_MESSAGE
        Configuration map mismatch between the JSON file and the generated file, please run `rake local_config_map:generate` and commit the changes.
        Please refer to `docs/AccessEnvironmentVariables.md` for more information.
      ERROR_MESSAGE

      expect(supported_configurations.sort).to eq(Datadog::Core::Configuration::SUPPORTED_CONFIGURATIONS.sort), error_message
      # check order of the keys
      expect(supported_configurations).to eq(Datadog::Core::Configuration::SUPPORTED_CONFIGURATIONS),
        "The keys in supported-configurations.json are not correctly sorted. Please keep the keys sorted alphabetically."

      # no need to check the order for these as they don't appear in the JSON file
      expect(aliases).to eq(Datadog::Core::Configuration::ALIASES), error_message
      expect(deprecations).to eq(Datadog::Core::Configuration::DEPRECATIONS), error_message
      expect(alias_to_canonical).to eq(Datadog::Core::Configuration::ALIAS_TO_CANONICAL), error_message
    end
  end
end
