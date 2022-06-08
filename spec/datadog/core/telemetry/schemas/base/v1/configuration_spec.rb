require 'spec_helper'

require 'datadog/core/telemetry/schemas/v1/base/configuration'

RSpec.describe Datadog::Core::Telemetry::Schemas::V1::Base::Configuration do
  describe '#initialize' do
    let(:name) { 'DD_TRACE_DEBUG' }
    let(:value) { 'true' }

    context 'given only required parameters' do
      subject(:configuration) { described_class.new(name: name) }
      it { is_expected.to be_a_kind_of(described_class) }
      it { is_expected.to have_attributes(name: name, value: nil) }
    end

    context 'given all parameters' do
      subject(:configuration) { described_class.new(name: name, value: value) }
      it { is_expected.to have_attributes(name: name, value: value) }
    end
  end
end
