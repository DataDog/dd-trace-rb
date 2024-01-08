require 'spec_helper'

require 'datadog/tracing/distributed/b3_multi'
require 'datadog/tracing/trace_digest'

RSpec.shared_examples 'B3 Multi distributed format' do
  let(:propagation_inject_style) { ['b3multi'] }
  let(:propagation_extract_style) { ['b3multi'] }

  let(:prepare_key) { defined?(super) ? super() : proc { |key| key } }

  describe '#inject!' do
    subject!(:inject!) { propagation.inject!(digest, data) }
    let(:data) { {} }

    context 'with nil digest' do
      let(:digest) { nil }
      it { is_expected.to be nil }
    end

    context 'with trace_id and span_id' do
      let(:digest) do
        Datadog::Tracing::TraceDigest.new(
          span_id: 0xabc,
          trace_id: 0xdef
        )
      end

      it do
        expect(data).to eq(
          'x-b3-spanid' => '0000000000000abc',
          'x-b3-traceid' => '00000000000000000000000000000def',
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
              span_id: 0xabc,
              trace_id: 0xdef,
              trace_sampling_priority: value
            )
          end

          it do
            expect(data).to eq(
              'x-b3-spanid' => '0000000000000abc',
              'x-b3-traceid' => '00000000000000000000000000000def',
              'x-b3-sampled' => expected.to_s
            )
          end
        end
      end

      context 'with origin' do
        let(:digest) do
          Datadog::Tracing::TraceDigest.new(
            span_id: 0xabc,
            trace_id: 0xdef,
            trace_origin: 'synthetics'
          )
        end

        it 'cannot propagate origin' do
          expect(data).to eq(
            'x-b3-spanid' => '0000000000000abc',
            'x-b3-traceid' => '00000000000000000000000000000def',
          )
        end
      end
    end

    context 'with 128 bit trace id and distributed tag `_dd.p.tid`' do
      let(:digest) do
        Datadog::Tracing::TraceDigest.new(
          trace_id: 0xaaaaaaaaaaaaaaaaffffffffffffffff,
          span_id: 0xbbbbbbbbbbbbbbbb
        )
      end

      it do
        inject!

        expect(data).to eq(
          'x-b3-traceid' => 'aaaaaaaaaaaaaaaaffffffffffffffff',
          'x-b3-spanid' => 'bbbbbbbbbbbbbbbb',
        )
      end
    end
  end

  describe '#extract' do
    subject(:extract) { propagation.extract(data) }
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

      context 'when given invalid trace id' do
        [
          ((1 << 128)).to_s(16), # 0
          ((1 << 128) + 1).to_s(16),
          '0',
          '-1',
        ].each do |invalid_trace_id|
          context "when given trace id: #{invalid_trace_id}" do
            let(:data) do
              {
                prepare_key['x-b3-traceid'] => invalid_trace_id,
                prepare_key['x-b3-spanid'] => 20000.to_s(16)
              }
            end

            it { is_expected.to be nil }
          end
        end
      end

      context 'when given invalid span id' do
        [
          ((1 << 64)).to_s(16),
          ((1 << 64) + 1).to_s(16),
          '0',
          '-1',
        ].each do |invalid_span_id|
          context "when given span id: #{invalid_span_id}" do
            let(:data) do
              {
                prepare_key['x-b3-traceid'] => 10000.to_s(16),
                prepare_key['x-b3-spanid'] => invalid_span_id,
              }
            end

            it { is_expected.to be nil }
          end
        end
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

    context 'with 128 bit trace id' do
      let(:data) do
        {
          prepare_key['x-b3-traceid'] => 'aaaaaaaaaaaaaaaaffffffffffffffff',
          prepare_key['x-b3-spanid'] => 'bbbbbbbbbbbbbbbb',
        }
      end

      it { expect(digest.trace_id).to eq(0xaaaaaaaaaaaaaaaaffffffffffffffff) }
      it { expect(digest.span_id).to eq(0xbbbbbbbbbbbbbbbb) }
    end
  end
end

RSpec.describe Datadog::Tracing::Distributed::B3Multi do
  subject(:propagation) { described_class.new(fetcher: fetcher_class) }
  let(:fetcher_class) { Datadog::Tracing::Distributed::Fetcher }

  it_behaves_like 'B3 Multi distributed format'
end
