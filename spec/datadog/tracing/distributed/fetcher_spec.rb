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
end
