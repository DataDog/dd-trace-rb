require 'spec_helper'

require 'datadog/tracing/distributed/b3_single'
require 'datadog/tracing/trace_digest'

RSpec.shared_examples 'B3 Single distributed format' do
  let(:propagation_inject_style) { ['b3'] }
  let(:propagation_extract_style) { ['b3'] }

  let(:prepare_key) { defined?(super) ? super() : proc { |key| key } }

  let(:b3_single_header) { 'b3' }

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

      it { expect(data).to eq(b3_single_header => '00000000000000000000000000000def-0000000000000abc') }

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

          it { expect(data).to eq(b3_single_header => "00000000000000000000000000000def-0000000000000abc-#{expected}") }
        end
      end

      context 'with origin' do
        let(:digest) do
          Datadog::Tracing::TraceDigest.new(
            trace_id: 0xabcdef,
            span_id: 0xfedcba,
            trace_origin: 'synthetics'
          )
        end

        it { expect(data).to eq(b3_single_header => '00000000000000000000000000abcdef-0000000000fedcba') }
      end
    end

    context 'with 128 bits trace id and distributed tag `_dd.p.tid`' do
      let(:digest) do
        Datadog::Tracing::TraceDigest.new(
          trace_id: 0xaaaaaaaaaaaaaaaaffffffffffffffff,
          span_id: 0xbbbbbbbbbbbbbbbb
        )
      end

      it do
        inject!

        expect(data).to eq(b3_single_header => 'aaaaaaaaaaaaaaaaffffffffffffffff-bbbbbbbbbbbbbbbb')
      end
    end
  end

  describe '#extract' do
    subject(:extract) { propagation.extract(data) }
    let(:digest) { extract }

    let(:data) { {} }

    context 'with empty data' do
      it { is_expected.to be nil }
    end

    context 'with trace_id and span_id' do
      let(:data) { { prepare_key[b3_single_header] => 'abcdef-fedcba' } }

      it { expect(digest.trace_id).to eq(0xabcdef) }
      it { expect(digest.span_id).to eq(0xfedcba) }
      it { expect(digest.trace_origin).to be nil }
      it { expect(digest.trace_sampling_priority).to be nil }

      context 'with sampling priority' do
        let(:data) { { prepare_key[b3_single_header] => 'abcdef-fedcba-1' } }

        it { expect(digest.trace_id).to eq(0xabcdef) }
        it { expect(digest.span_id).to eq(0xfedcba) }
        it { expect(digest.trace_origin).to be nil }
        it { expect(digest.trace_sampling_priority).to eq(1) }

        context 'with parent_id' do
          let(:data) do
            {
              prepare_key[b3_single_header] => 'abcdef-fedcba-1-4e20'
            }
          end

          it { expect(digest.trace_id).to eq(0xabcdef) }
          it { expect(digest.span_id).to eq(0xfedcba) }
          it { expect(digest.trace_sampling_priority).to eq(1) }
          it { expect(digest.trace_origin).to be nil }
        end
      end

      context 'when given invalid trace id' do
        [
          ((1 << 128)).to_s(16), # 0
          ((1 << 128) + 1).to_s(16),
          '0',
          '-1',
        ].each do |invalid_trace_id|
          context "when given trace id: #{invalid_trace_id}" do
            let(:data) { { prepare_key[b3_single_header] => "#{invalid_trace_id}-fedcba" } }

            it { is_expected.to be nil }
          end
        end
      end

      context 'when given invalid span id' do
        [
          ((1 << 64)).to_s(16),
          ((1 << 64) + 1).to_s(16),
          '0',
        ].each do |invalid_span_id|
          context "when given span id: #{invalid_span_id}" do
            let(:data) { { prepare_key[b3_single_header] => "abcdef-#{invalid_span_id}" } }

            it { is_expected.to be nil }
          end
        end
      end
    end

    context 'with trace_id' do
      let(:data) { { prepare_key[b3_single_header] => 'abcdef' } }

      it { is_expected.to be nil }

      context 'with 128 bits trace id and 64 bits span id' do
        let(:data) do
          { prepare_key[b3_single_header] => 'aaaaaaaaaaaaaaaaffffffffffffffff-bbbbbbbbbbbbbbbb' }
        end

        it { expect(digest.trace_id).to eq(0xaaaaaaaaaaaaaaaaffffffffffffffff) }
        it { expect(digest.span_id).to eq(0xbbbbbbbbbbbbbbbb) }
      end
    end
  end
end

RSpec.describe Datadog::Tracing::Distributed::B3Single do
  subject(:propagation) { described_class.new(fetcher: fetcher_class) }
  let(:fetcher_class) { Datadog::Tracing::Distributed::Fetcher }

  it_behaves_like 'B3 Single distributed format'
end
