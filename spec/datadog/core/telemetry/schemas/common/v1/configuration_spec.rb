require 'spec_helper'

require 'datadog/core/telemetry/schemas/common/v1/configuration'

RSpec.describe Datadog::Core::Telemetry::Schemas::Common::V1::Configuration do
  subject(:custom_kv) { described_class.new(name, value) }

  describe '#initialize' do
    let(:name) { '' }
    let(:value) { '' }
    it { is_expected.to be_a_kind_of(described_class) }

    context 'given parameters' do
      it {
        is_expected.to have_attributes(name: name, value: value)
      }
    end
  end
end
