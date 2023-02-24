require 'spec_helper'

require 'datadog/tracing/distributed/b3_multi'
require 'datadog/tracing/trace_digest'

RSpec.shared_examples 'B3 Multi distributed format' do
  subject(:b3) { described_class.new(fetcher: fetcher_class) }
  let(:fetcher_class) { Datadog::Tracing::Distributed::Fetcher }

  let(:prepare_key) { defined?(super) ? super() : proc { |key| key } }

  describe '#inject!' do
    subject!(:inject!) { b3.inject!(digest, data) }
    let(:data) { {} }

    context 'with nil digest' do
      let(:digest) { nil }
      it { is_expected.to be nil }
    end

    context 'with trace_id and span_id' do
      let(:digest) do
        Datadog::Tracing::TraceDigest.new(
          span_id: 20000,
          trace_id: 10000
        )
      end

      it do
        expect(data).to eq(
          'x-b3-traceid' => 10000.to_s(16),
          'x-b3-spanid' => 20000.to_s(16)
        )
      end

      [
        [-1, 0],
        [0, 0],
        [1, 1],
        [2, 1]
      ].each do |value, expected|
        context "with sampling priority #{value}" do
          let(:digest) do
            Datadog::Tracing::TraceDigest.new(
              span_id: 60000,
              trace_id: 50000,
              trace_sampling_priority: value
            )
          end

          it do
            expect(data).to eq(
              'x-b3-traceid' => 50000.to_s(16),
              'x-b3-spanid' => 60000.to_s(16),
              'x-b3-sampled' => expected.to_s
            )
          end
        end
      end

      context 'with origin' do
        let(:digest) do
          Datadog::Tracing::TraceDigest.new(
            span_id: 100000,
            trace_id: 90000,
            trace_origin: 'synthetics'
          )
        end

        it do
          expect(data).to eq(
            'x-b3-traceid' => 90000.to_s(16),
            'x-b3-spanid' => 100000.to_s(16)
          )
        end
      end
    end
  end

  describe '#extract' do
    subject(:extract) { b3.extract(data) }
    let(:digest) { extract }

    let(:data) { {} }

    context 'with empty data' do
      it { is_expected.to be_nil }
    end

    context 'with trace_id and span_id' do
      let(:data) do
        { prepare_key['x-b3-traceid'] => 10000.to_s(16),
          prepare_key['x-b3-spanid'] => 20000.to_s(16) }
      end

      it { expect(digest.span_id).to eq(20000) }
      it { expect(digest.trace_id).to eq(10000) }
      it { expect(digest.trace_origin).to be nil }
      it { expect(digest.trace_sampling_priority).to be nil }

      context 'with sampling priority' do
        let(:data) do
          { prepare_key['x-b3-traceid'] => 10000.to_s(16),
            prepare_key['x-b3-spanid'] => 20000.to_s(16),
            prepare_key['x-b3-sampled'] => '1' }
        end

        it { expect(digest.span_id).to eq(20000) }
        it { expect(digest.trace_id).to eq(10000) }
        it { expect(digest.trace_origin).to be nil }
        it { expect(digest.trace_sampling_priority).to eq(1) }
      end

      context 'with origin' do
        let(:data) do
          { prepare_key['x-b3-traceid'] => 10000.to_s(16),
            prepare_key['x-b3-spanid'] => 20000.to_s(16),
            prepare_key['x-datadog-origin'] => 'synthetics' }
        end

        it { expect(digest.span_id).to eq(20000) }
        it { expect(digest.trace_id).to eq(10000) }
        it { expect(digest.trace_sampling_priority).to be nil }
        it { expect(digest.trace_origin).to be nil }
      end
    end

    context 'with span_id' do
      let(:data) { { prepare_key['x-b3-spanid'] => 10000.to_s(16) } }

      it { is_expected.to be nil }
    end

    context 'with sampling priority' do
      let(:data) { { prepare_key['x-b3-sampled'] => '1' } }

      it { is_expected.to be nil }
    end

    context 'with trace_id' do
      let(:data) { { prepare_key['x-b3-traceid'] => 10000.to_s(16) } }

      it { is_expected.to be nil }
    end
  end
end

RSpec.describe Datadog::Tracing::Distributed::B3Multi do
  it_behaves_like 'B3 Multi distributed format'
end
