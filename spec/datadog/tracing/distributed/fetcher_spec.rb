require 'spec_helper'

require 'datadog/tracing/distributed/fetcher'
require 'datadog/tracing/span'

RSpec.describe Datadog::Tracing::Distributed::Fetcher do
  subject(:fetcher) { described_class.new(data) }

  let(:data) { {} }

  describe '#[]' do
    subject(:get) { fetcher[key] }
    let(:key) {}

    context 'with no value associated' do
      let(:key) { 'not present' }
      it { is_expected.to be_nil }
    end

    context 'with a value associated' do
      let(:data) { { key => 'value' } }
      it { is_expected.to eq('value') }
    end
  end

  describe '#id' do
    subject(:id) { fetcher.id(key, base: base) }
    let(:data) { { key => value } }
    let(:key) { double('key') }
    let(:value) { double('value') }
    let(:base) { double('base') }

    it 'delegates to Datadog::Tracing::Distributed::Helpers.value_to_id' do
      ret = double('return')
      expect(Datadog::Tracing::Distributed::Helpers).to receive(:value_to_id).with(value, base: base).and_return(ret)
      is_expected.to eq(ret)
    end
  end

  describe '#number' do
    subject(:number) { fetcher.number(key, base: base) }
    let(:data) { { key => value } }
    let(:key) { double('key') }
    let(:value) { double('value') }
    let(:base) { double('base') }

    it 'delegates to Datadog::Tracing::Distributed::Helpers.value_to_number' do
      ret = double('return')
      expect(Datadog::Tracing::Distributed::Helpers).to receive(:value_to_number).with(value, base: base).and_return(ret)
      is_expected.to eq(ret)
    end
  end
end
