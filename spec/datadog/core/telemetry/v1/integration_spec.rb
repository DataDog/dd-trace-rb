require 'spec_helper'

require 'datadog/core/telemetry/v1/integration'
require 'datadog/core/telemetry/v1/shared_examples'

RSpec.describe Datadog::Core::Telemetry::V1::Integration do
  subject(:integration) do
    described_class.new(
      auto_enabled: auto_enabled,
      compatible: compatible,
      enabled: enabled,
      error: error,
      name: name,
      version: version
    )
  end

  let(:auto_enabled) { false }
  let(:compatible) { true }
  let(:enabled) { false }
  let(:error) { 'Failed to enable' }
  let(:name) { 'pg' }
  let(:version) { '1.7.0' }

  it do
    is_expected.to have_attributes(
      auto_enabled: auto_enabled,
      compatible: compatible,
      enabled: enabled,
      error: error,
      name: name,
      version: version
    )
  end

  describe '#initialize' do
    context ':auto_enabled' do
      it_behaves_like 'an optional boolean parameter', 'auto_enabled'
    end

    context ':compatible' do
      it_behaves_like 'an optional boolean parameter', 'compatible'
    end

    context ':enabled' do
      it_behaves_like 'a required boolean parameter', 'enabled'
    end

    context ':error' do
      it_behaves_like 'an optional string parameter', 'error'
    end

    context ':name' do
      it_behaves_like 'a required string parameter', 'name'
    end

    context ':version' do
      it_behaves_like 'an optional string parameter', 'version'
    end
  end

  describe '#to_h' do
    subject(:to_h) { integration.to_h }

    let(:auto_enabled) { false }
    let(:compatible) { true }
    let(:enabled) { false }
    let(:error) { 'Failed to enable' }
    let(:name) { 'pg' }
    let(:version) { '1.7.0' }

    it do
      is_expected.to eq(
        auto_enabled: auto_enabled,
        compatible: compatible,
        enabled: enabled,
        error: error,
        name: name,
        version: version
      )
    end
  end
end
