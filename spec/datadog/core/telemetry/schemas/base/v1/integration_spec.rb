require 'spec_helper'

require 'datadog/core/telemetry/schemas/base/v1/integration'

RSpec.describe Datadog::Core::Telemetry::Schemas::Base::V1::Integration do
  describe '#initialize' do
    let(:name) { 'pg' }
    let(:enabled) { false }
    let(:version) { '1.7.0' }
    let(:auto_enabled) { false }
    let(:compatible) { true }
    let(:error) { 'Failed to enable' }

    context 'given only required parameters' do
      subject(:integration) { described_class.new(name, enabled) }
      it { is_expected.to be_a_kind_of(described_class) }
      it { is_expected.to have_attributes(name: name, enabled: enabled) }

      it {
        is_expected.to have_attributes(version: nil, auto_enabled: nil,
                                       compatible: nil, error: nil)
      }
    end

    context 'given all parameters' do
      subject(:integration) { described_class.new(name, enabled, version, auto_enabled, compatible, error) }
      it {
        is_expected.to have_attributes(name: name, enabled: enabled, version: version, auto_enabled: auto_enabled,
                                       compatible: compatible, error: error)
      }
    end
  end
end
