# typed: false
require 'spec_helper'

require 'ddtrace'
require 'ddtrace/context'
require 'ddtrace/ext/distributed'
require 'ddtrace/distributed_tracing/headers/b3_single'

RSpec.describe Datadog::DistributedTracing::Headers::B3Single do
  # Header format:
  #   b3: {TraceId}-{SpanId}-{SamplingState}-{ParentSpanId}
  # https://github.com/apache/incubator-zipkin-b3-propagation/tree/7c6e9f14d6627832bd80baa87ac7dabee7be23cf#single-header
  # DEV: `{SamplingState}` and `{ParentSpanId`}` are optional

  let(:context) { Datadog.Context.new }

  # Helper to format env header keys
  def env_header(name)
    "http-#{name}".upcase!.tr('-', '_')
  end

  describe '#inject!' do
    subject!(:inject!) { described_class.inject!(digest, env) }
    let(:env) { {} }

    context 'with nil context' do
      let(:digest) { nil }
      it { is_expected.to be nil }
    end

    context 'with trace_id and span_id' do
      let(:digest) do
        Datadog::TraceDigest.new(
          span_id: 20000,
          trace_id: 10000
        )
      end

      it { is_expected.to eq(Datadog::Ext::DistributedTracing::B3_HEADER_SINGLE => '2710-4e20') }

      [
        [-1, 0],
        [0, 0],
        [1, 1],
        [2, 1]
      ].each do |value, expected|
        context "with sampling priority #{value}" do
          let(:digest) do
            Datadog::TraceDigest.new(
              span_id: 60000,
              trace_id: 50000,
              trace_sampling_priority: value
            )
          end

          it { is_expected.to eq(Datadog::Ext::DistributedTracing::B3_HEADER_SINGLE => "c350-ea60-#{expected}") }
        end
      end

      context 'with origin' do
        let(:digest) do
          Datadog::TraceDigest.new(
            span_id: 100000,
            trace_id: 90000,
            trace_origin: 'synthetics'
          )
        end

        it { is_expected.to eq(Datadog::Ext::DistributedTracing::B3_HEADER_SINGLE => '15f90-186a0') }
      end
    end
  end

  describe '#extract' do
    subject(:extract) { described_class.extract(env) }
    let(:digest) { extract }

    let(:env) { {} }

    context 'with empty env' do
      it { is_expected.to be nil }
    end

    context 'with trace_id and span_id' do
      let(:env) { { env_header(Datadog::Ext::DistributedTracing::B3_HEADER_SINGLE) => '15f90-186a0' } }

      it { expect(digest.span_id).to eq(100000) }
      it { expect(digest.trace_id).to eq(90000) }
      it { expect(digest.trace_origin).to be nil }
      it { expect(digest.trace_sampling_priority).to be nil }

      context 'with sampling priority' do
        let(:env) { { env_header(Datadog::Ext::DistributedTracing::B3_HEADER_SINGLE) => '15f90-186a0-1' } }

        it { expect(digest.span_id).to eq(100000) }
        it { expect(digest.trace_id).to eq(90000) }
        it { expect(digest.trace_origin).to be nil }
        it { expect(digest.trace_sampling_priority).to eq(1) }

        context 'with parent_id' do
          let(:env) { { env_header(Datadog::Ext::DistributedTracing::B3_HEADER_SINGLE) => '15f90-186a0-1-4e20' } }

          it { expect(digest.trace_id).to eq(90000) }
          it { expect(digest.span_id).to eq(100000) }
          it { expect(digest.trace_sampling_priority).to eq(1) }
          it { expect(digest.trace_origin).to be nil }
        end
      end
    end

    context 'with trace_id' do
      let(:env) { { env_header(Datadog::Ext::DistributedTracing::B3_HEADER_SINGLE) => '15f90' } }

      it { is_expected.to be nil }
    end
  end
end
