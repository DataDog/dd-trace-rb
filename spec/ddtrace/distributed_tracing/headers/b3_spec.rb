# typed: false
require 'spec_helper'

require 'ddtrace'
require 'ddtrace/context'
require 'ddtrace/ext/distributed'
require 'ddtrace/distributed_tracing/headers/b3'

RSpec.describe Datadog::DistributedTracing::Headers::B3 do
  let(:context) { Datadog::Context.new }

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

      it do
        expect(env).to eq(Datadog::Ext::DistributedTracing::B3_HEADER_TRACE_ID => 10000.to_s(16),
                          Datadog::Ext::DistributedTracing::B3_HEADER_SPAN_ID => 20000.to_s(16))
      end

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

          it do
            expect(env).to eq(Datadog::Ext::DistributedTracing::B3_HEADER_TRACE_ID => 50000.to_s(16),
                              Datadog::Ext::DistributedTracing::B3_HEADER_SPAN_ID => 60000.to_s(16),
                              Datadog::Ext::DistributedTracing::B3_HEADER_SAMPLED => expected.to_s)
          end
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

        it do
          expect(env).to eq(Datadog::Ext::DistributedTracing::B3_HEADER_TRACE_ID => 90000.to_s(16),
                            Datadog::Ext::DistributedTracing::B3_HEADER_SPAN_ID => 100000.to_s(16))
        end
      end
    end
  end

  describe '#extract' do
    subject(:extract) { described_class.extract(env) }
    let(:digest) { extract }

    let(:env) { {} }

    context 'with empty env' do
      it { is_expected.to be_nil }
    end

    context 'with trace_id and span_id' do
      let(:env) do
        { env_header(Datadog::Ext::DistributedTracing::B3_HEADER_TRACE_ID) => 10000.to_s(16),
          env_header(Datadog::Ext::DistributedTracing::B3_HEADER_SPAN_ID) => 20000.to_s(16) }
      end

      it { expect(digest.span_id).to eq(20000) }
      it { expect(digest.trace_id).to eq(10000) }
      it { expect(digest.trace_origin).to be nil }
      it { expect(digest.trace_sampling_priority).to be nil }

      context 'with sampling priority' do
        let(:env) do
          { env_header(Datadog::Ext::DistributedTracing::B3_HEADER_TRACE_ID) => 10000.to_s(16),
            env_header(Datadog::Ext::DistributedTracing::B3_HEADER_SPAN_ID) => 20000.to_s(16),
            env_header(Datadog::Ext::DistributedTracing::B3_HEADER_SAMPLED) => '1' }
        end

        it { expect(digest.span_id).to eq(20000) }
        it { expect(digest.trace_id).to eq(10000) }
        it { expect(digest.trace_origin).to be nil }
        it { expect(digest.trace_sampling_priority).to eq(1) }
      end

      context 'with origin' do
        let(:env) do
          { env_header(Datadog::Ext::DistributedTracing::B3_HEADER_TRACE_ID) => 10000.to_s(16),
            env_header(Datadog::Ext::DistributedTracing::B3_HEADER_SPAN_ID) => 20000.to_s(16),
            env_header(Datadog::Ext::DistributedTracing::HTTP_HEADER_ORIGIN) => 'synthetics' }
        end

        it { expect(digest.span_id).to eq(20000) }
        it { expect(digest.trace_id).to eq(10000) }
        it { expect(digest.trace_sampling_priority).to be nil }
        it { expect(digest.trace_origin).to be nil }
      end
    end

    context 'with span_id' do
      let(:env) { { env_header(Datadog::Ext::DistributedTracing::B3_HEADER_SPAN_ID) => 10000.to_s(16) } }

      it { is_expected.to be nil }
    end

    context 'with sampling priority' do
      let(:env) { { env_header(Datadog::Ext::DistributedTracing::B3_HEADER_SAMPLED) => '1' } }

      it { is_expected.to be nil }
    end

    context 'with trace_id' do
      let(:env) { { env_header(Datadog::Ext::DistributedTracing::B3_HEADER_TRACE_ID) => 10000.to_s(16) } }

      it { is_expected.to be nil }
    end
  end
end
