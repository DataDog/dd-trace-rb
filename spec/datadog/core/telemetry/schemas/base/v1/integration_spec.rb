require 'spec_helper'

require 'datadog/core/telemetry/schemas/v1/base/integration'

RSpec.describe Datadog::Core::Telemetry::Schemas::V1::Base::Integration do
  describe '#initialize' do
    let(:auto_enabled) { false }
    let(:compatible) { true }
    let(:enabled) { false }
    let(:error) { 'Failed to enable' }
    let(:name) { 'pg' }
    let(:version) { '1.7.0' }

    context 'given only required parameters' do
      subject(:integration) { described_class.new(name: name, enabled: enabled) }
      it { is_expected.to be_a_kind_of(described_class) }
      it { is_expected.to have_attributes(name: name, enabled: enabled) }
      it { is_expected.to have_attributes(version: nil, auto_enabled: nil, compatible: nil, error: nil) }
    end

    context 'given all parameters' do
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
    end
  end
end
