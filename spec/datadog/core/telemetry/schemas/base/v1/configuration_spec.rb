require 'spec_helper'

require 'datadog/core/telemetry/schemas/base/v1/configuration'

RSpec.describe Datadog::Core::Telemetry::Schemas::Base::V1::Configuration do
  describe '#initialize' do
    let(:name) { 'DD_TRACE_DEBUG' }
    let(:value) { 'true' }

    context 'given only required parameters' do
      subject(:configuration) { described_class.new(name) }
      it { is_expected.to be_a_kind_of(described_class) }
      it { is_expected.to have_attributes(name: name, value: nil) }
    end

    context 'given all parameters' do
      subject(:configuration) { described_class.new(name, value) }
      it { is_expected.to have_attributes(name: name, value: value) }
    end
  end
end
