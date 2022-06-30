# typed: false

require 'spec_helper'

require 'datadog/tracing/distributed/headers/ext'
require 'datadog/tracing/distributed/metadata/b3_single'
require 'datadog/tracing/trace_digest'

RSpec.describe Datadog::Tracing::Distributed::Metadata::B3Single do
  # Header format:
  #   b3: {TraceId}-{SpanId}-{SamplingState}-{ParentSpanId}
  # https://github.com/apache/incubator-zipkin-b3-propagation/tree/7c6e9f14d6627832bd80baa87ac7dabee7be23cf#single-header
  # DEV: `{SamplingState}` and `{ParentSpanId`}` are optional

  describe '#inject!' do
    subject!(:inject!) { described_class.inject!(digest, metadata) }
    let(:metadata) { {} }

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

      it { is_expected.to eq(Datadog::Tracing::Distributed::Headers::Ext::B3_HEADER_SINGLE => '2710-4e20') }

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

          it {
            is_expected.to eq(Datadog::Tracing::Distributed::Headers::Ext::B3_HEADER_SINGLE => "c350-ea60-#{expected}")
          }
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

        it { is_expected.to eq(Datadog::Tracing::Distributed::Headers::Ext::B3_HEADER_SINGLE => '15f90-186a0') }
      end
    end
  end

  describe '#extract' do
    subject(:extract) { described_class.extract(metadata) }
    let(:digest) { extract }

    let(:metadata) { {} }

    context 'with empty metadata' do
      it { is_expected.to be nil }
    end

    context 'with trace_id and span_id' do
      let(:metadata) { { Datadog::Tracing::Distributed::Headers::Ext::B3_HEADER_SINGLE => '15f90-186a0' } }

      it { expect(digest.span_id).to eq(100000) }
      it { expect(digest.trace_id).to eq(90000) }
      it { expect(digest.trace_origin).to be nil }
      it { expect(digest.trace_sampling_priority).to be nil }

      context 'with sampling priority' do
        let(:metadata) { { Datadog::Tracing::Distributed::Headers::Ext::B3_HEADER_SINGLE => '15f90-186a0-1' } }

        it { expect(digest.span_id).to eq(100000) }
        it { expect(digest.trace_id).to eq(90000) }
        it { expect(digest.trace_origin).to be nil }
        it { expect(digest.trace_sampling_priority).to eq(1) }

        context 'with parent_id' do
          let(:metadata) do
            {
              Datadog::Tracing::Distributed::Headers::Ext::B3_HEADER_SINGLE => '15f90-186a0-1-4e20'
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
      let(:env) { { Datadog::Tracing::Distributed::Headers::Ext::B3_HEADER_SINGLE => '15f90' } }

      it { is_expected.to be nil }
    end
  end
end
