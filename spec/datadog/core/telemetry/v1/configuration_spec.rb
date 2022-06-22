require 'spec_helper'

require 'datadog/core/telemetry/v1/configuration'

RSpec.describe Datadog::Core::Telemetry::V1::Configuration do
  subject(:configuration) { described_class.new(name: name, value: value) }

  let(:name) { 'DD_TRACE_DEBUG' }
  let(:value) { true }

  it { is_expected.to have_attributes(name: name, value: value) }

  describe '#initialize' do
    context ':name' do
      it_behaves_like 'a required string parameter', 'name'
    end

    context 'when :value' do
      context 'is nil' do
        let(:value) { nil }
        it { is_expected.to be_a_kind_of(described_class) }
      end

      context 'is string' do
        let(:value) { 'true' }
        it { is_expected.to be_a_kind_of(described_class) }
      end

      context 'is bool' do
        let(:value) { true }
        it { is_expected.to be_a_kind_of(described_class) }
      end

      context 'is int' do
        let(:value) { 1 }
        it { is_expected.to be_a_kind_of(described_class) }
      end
    end
  end
end
