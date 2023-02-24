require 'spec_helper'

require 'datadog/tracing/distributed/b3_single'
require 'datadog/tracing/trace_digest'

RSpec.shared_examples 'B3 Single distributed format' do
  subject(:b3_single) { described_class.new(fetcher: fetcher_class) }
  let(:fetcher_class) { Datadog::Tracing::Distributed::Fetcher }

  let(:prepare_key) { defined?(super) ? super() : proc { |key| key } }

  let(:b3_single_header) { 'b3' }

  describe '#inject!' do
    subject!(:inject!) { b3_single.inject!(digest, data) }
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

      it { expect(data).to eq(b3_single_header => '2710-4e20') }

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

          it { expect(data).to eq(b3_single_header => "c350-ea60-#{expected}") }
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

        it { expect(data).to eq(b3_single_header => '15f90-186a0') }
      end
    end
  end

  describe '#extract' do
    subject(:extract) { b3_single.extract(data) }
    let(:digest) { extract }

    let(:data) { {} }

    context 'with empty data' do
      it { is_expected.to be nil }
    end

    context 'with trace_id and span_id' do
      let(:data) { { prepare_key[b3_single_header] => '15f90-186a0' } }

      it { expect(digest.span_id).to eq(100000) }
      it { expect(digest.trace_id).to eq(90000) }
      it { expect(digest.trace_origin).to be nil }
      it { expect(digest.trace_sampling_priority).to be nil }

      context 'with sampling priority' do
        let(:data) { { prepare_key[b3_single_header] => '15f90-186a0-1' } }

        it { expect(digest.span_id).to eq(100000) }
        it { expect(digest.trace_id).to eq(90000) }
        it { expect(digest.trace_origin).to be nil }
        it { expect(digest.trace_sampling_priority).to eq(1) }

        context 'with parent_id' do
          let(:data) do
            {
              prepare_key[b3_single_header] => '15f90-186a0-1-4e20'
            }
          end

          it { expect(digest.trace_id).to eq(90000) }
          it { expect(digest.span_id).to eq(100000) }
          it { expect(digest.trace_sampling_priority).to eq(1) }
          it { expect(digest.trace_origin).to be nil }
        end
      end
    end

    context 'with trace_id' do
      let(:env) { { prepare_key[b3_single_header] => '15f90' } }

      it { is_expected.to be nil }
    end
  end
end

RSpec.describe Datadog::Tracing::Distributed::B3Single do
  it_behaves_like 'B3 Single distributed format'
end
