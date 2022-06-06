require 'spec_helper'

require 'datadog/core/telemetry/schemas/common/v1/dependency'

RSpec.describe Datadog::Core::Telemetry::Schemas::Common::V1::Dependency do
  subject(:dependency) { described_class.new(name, version, hash) }

  describe '#initialize' do
    let(:name) { '' }
    let(:version) { '1.0' }
    let(:hash) { 'abcdefghijklmnop123' }
    it { is_expected.to be_a_kind_of(described_class) }

    context 'given parameters' do
      it {
        is_expected.to have_attributes(name: name, version: version, hash: hash)
      }
    end
  end
end
