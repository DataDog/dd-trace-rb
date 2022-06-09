require 'spec_helper'

require 'datadog/core/telemetry/schemas/v1/base/configuration'

RSpec.describe Datadog::Core::Telemetry::Schemas::V1::Base::Configuration do
  subject(:configuration) { described_class.new(name: name, value: value) }

  let(:name) { 'DD_TRACE_DEBUG' }
  let(:value) { true }

  it { is_expected.to have_attributes(name: name, value: value) }

  describe '#initialize' do
    context 'when :name' do
      it_behaves_like 'a string argument', 'name'
    end

    context 'when :value' do
      it_behaves_like 'an optional string argument', 'value'

      context 'is valid bool' do
        let(:value) { true }
        it { is_expected.to be_a_kind_of(described_class) }
      end

      context 'is valid int' do
        let(:value) { 1 }
        it { is_expected.to be_a_kind_of(described_class) }
      end
    end
  end
end
