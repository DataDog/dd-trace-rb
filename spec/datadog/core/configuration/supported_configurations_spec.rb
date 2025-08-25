# frozen_string_literal: true

require 'spec_helper'
require 'json'

RSpec.describe 'Supported configurations' do
  describe 'consistency validation' do
    it 'validates that the generated data matches the JSON file' do
      json_data = JSON.parse(File.read('supported-configurations.json')).transform_keys(&:to_sym)
      json_data[:supportedConfigurations].each_value { |config| config.transform_keys!(&:to_sym) }
      alias_to_canonical = json_data[:aliases].each_with_object({}) do |(canonical, alias_list), h|
        alias_list.each do |alias_name|
          raise "The alias #{alias_name} is already used for #{h[alias_name]}." if h[alias_name]

          h[alias_name] = canonical
        end
      end

      error_message = <<~ERROR_MESSAGE
        Configuration map mismatch between the JSON file and the generated file, please run `rake local_config_map:generate` and commit the changes.
        Please refer to `docs/AccessEnvironmentVariables.md` for more information.
      ERROR_MESSAGE

      expect(json_data[:supportedConfigurations]).to eq(Datadog::Core::Configuration::SUPPORTED_CONFIGURATIONS), error_message
      expect(json_data[:aliases]).to eq(Datadog::Core::Configuration::ALIASES), error_message
      expect(json_data[:deprecations]).to eq(Datadog::Core::Configuration::DEPRECATIONS), error_message
      expect(alias_to_canonical).to eq(Datadog::Core::Configuration::ALIAS_TO_CANONICAL), error_message
    end
  end
end
