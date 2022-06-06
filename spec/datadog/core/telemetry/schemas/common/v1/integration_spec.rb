require 'spec_helper'

require 'datadog/core/telemetry/schemas/common/v1/integration'

RSpec.describe Datadog::Core::Telemetry::Schemas::Common::V1::Integration do
  subject(:integration) { described_class.new(name, enabled, version, auto_enabled, compatible, error) }

  describe '#initialize' do
    let(:name) { '' }
    let(:enabled) { true }
    let(:version) { '1.0' }
    let(:auto_enabled) { false }
    let(:compatible) { true }
    let(:error) { '' }
    it { is_expected.to be_a_kind_of(described_class) }

    context 'given parameters' do
      it {
        is_expected.to have_attributes(name: name, enabled: enabled, version: version, auto_enabled: auto_enabled,
                                       compatible: compatible, error: error)
      }
    end
  end
end
