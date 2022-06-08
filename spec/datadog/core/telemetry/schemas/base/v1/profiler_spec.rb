require 'spec_helper'

require 'datadog/core/telemetry/schemas/v1/base/profiler'

RSpec.describe Datadog::Core::Telemetry::Schemas::V1::Base::Profiler do
  describe '#initialize' do
    let(:version) { '1.0' }

    subject(:profiler) { described_class.new(version) }
    it { is_expected.to be_a_kind_of(described_class) }
    it { is_expected.to have_attributes(version: version) }
  end
end
