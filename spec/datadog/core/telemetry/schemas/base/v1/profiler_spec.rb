require 'spec_helper'

require 'datadog/core/telemetry/schemas/base/v1/profiler'

RSpec.describe Datadog::Core::Telemetry::Schemas::Base::V1::Profiler do
  describe '#initialize' do
    let(:version) { '1.0' }

    subject(:profiler) { described_class.new(version) }
    it { is_expected.to be_a_kind_of(described_class) }
    it { is_expected.to have_attributes(version: version) }
  end
end
