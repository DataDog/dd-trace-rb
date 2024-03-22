require 'datadog/tracing/contrib/support/spec_helper'

require 'datadog/tracing/contrib/http'

RSpec.describe Datadog::Tracing::Contrib::HTTP do
  context 'integration test' do
    before { Datadog.configure {} }

    let(:config) { Datadog.configuration }

    describe '#inject' do
      subject(:inject) { described_class.inject(digest, data) }
      let(:digest) { Datadog::Tracing::TraceDigest.new }
      let(:data) { {} }

      it 'injects distributed headers' do
        inject
        expect(data).to include('x-datadog-trace-id')
        expect(data).to include('x-datadog-parent-id')
      end
    end

    describe '#extract' do
      subject(:extract) { described_class.extract(data) }

      let(:data) { { 'x-datadog-trace-id' => '1', 'x-datadog-parent-id' => '2' } }

      it 'extracts distributed headers' do
        is_expected.to be_a_kind_of(Datadog::Tracing::TraceDigest)
      end
    end
  end
end
