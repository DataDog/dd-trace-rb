# frozen_string_literal: true

require 'spec_helper'

require 'datadog/core/telemetry/v2/app_client_configuration_change'

RSpec.describe Datadog::Core::Telemetry::V2::AppClientConfigurationChange do
  subject(:app_client_configuration_change) { described_class.new(configuration_changes, origin: origin) }

  let(:origin) { 'test-origin' }
  let(:configuration_changes) do
    [
      ['name1', 'value1'],
      ['name2', 'value2']
    ]
  end

  describe '#to_h' do
    subject(:to_h) { app_client_configuration_change.to_h }

    it 'includes request_type, configuration changes, and origin' do
      is_expected.to eq(
        {
          request_type: 'app-client-configuration-change',
          payload: {
            configuration: [
              {
                name: 'name1',
                value: 'value1',
                origin: 'test-origin',
              },
              {
                name: 'name2',
                value: 'value2',
                origin: 'test-origin',
              }
            ]
          }
        }
      )
    end
  end
end
