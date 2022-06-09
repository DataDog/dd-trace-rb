require 'spec_helper'

require 'datadog/core/telemetry/schemas/v1/base/integration'
require 'datadog/core/telemetry/schemas/shared_examples'

RSpec.describe Datadog::Core::Telemetry::Schemas::V1::Base::Integration do
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
    context 'when :auto_enabled' do
      it_behaves_like 'an optional boolean argument', 'auto_enabled'
    end

    context 'when :compatible' do
      it_behaves_like 'an optional boolean argument', 'compatible'
    end

    context 'when :enabled' do
      it_behaves_like 'a boolean argument', 'enabled'
    end

    context 'when :error' do
      it_behaves_like 'an optional string argument', 'error'
    end

    context 'when :name' do
      it_behaves_like 'a string argument', 'name'
    end

    context 'when :version' do
      it_behaves_like 'an optional string argument', 'version'
    end
  end
end
