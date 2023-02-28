require 'spec_helper'

require 'datadog/tracing/contrib/grpc/distributed/fetcher'

RSpec.describe Datadog::Tracing::Contrib::GRPC::Distributed::Fetcher do
  subject(:fetcher) { described_class.new(metadata) }

  let(:metadata) { {} }

  describe '#[]' do
    subject(:get) { fetcher[key] }
    let(:key) {}

    context 'with no value associated' do
      let(:key) { 'not present' }
      it { is_expected.to be_nil }
    end

    context 'with a string value associated' do
      let(:metadata) { { key => 'value' } }
      it { is_expected.to eq('value') }
    end

    context 'with an array value associated' do
      let(:metadata) { { key => %w[first last] } }
      it 'returns the first value' do
        is_expected.to eq('first')
      end
    end
  end
end
