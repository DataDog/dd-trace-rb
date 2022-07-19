# typed: false

require 'spec_helper'

require 'datadog/tracing/distributed/headers/ext'
require 'datadog/tracing/distributed/headers/datadog'
require 'datadog/tracing/trace_digest'

RSpec.describe Datadog::Tracing::Distributed::Headers::Datadog do
  # Helper to format env header keys
  def env_header(name)
    "http-#{name}".upcase!.tr('-', '_')
  end

  describe '#inject!' do
    subject!(:inject!) { described_class.inject!(digest, env) }
    let(:env) { {} }

    context 'with nil digest' do
      let(:digest) { nil }
      it { is_expected.to be nil }
    end

    context 'with TraceDigest' do
      let(:digest) do
        Datadog::Tracing::TraceDigest.new(
          trace_id: 10000,
          span_id: 20000
        )
      end

      it do
        expect(env).to eq(Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_TRACE_ID => '10000',
          Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_PARENT_ID => '20000')
      end

      context 'with sampling priority' do
        let(:digest) do
          Datadog::Tracing::TraceDigest.new(
            span_id: 60000,
            trace_id: 50000,
            trace_sampling_priority: 1
          )
        end

        it do
          expect(env).to eq(Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_TRACE_ID => '50000',
            Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_PARENT_ID => '60000',
            Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_SAMPLING_PRIORITY => '1')
        end

        context 'with origin' do
          let(:digest) do
            Datadog::Tracing::TraceDigest.new(
              span_id: 80000,
              trace_id: 70000,
              trace_origin: 'synthetics',
              trace_sampling_priority: 1
            )
          end

          it do
            expect(env).to eq(Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_TRACE_ID => '70000',
              Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_PARENT_ID => '80000',
              Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_SAMPLING_PRIORITY => '1',
              Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_ORIGIN => 'synthetics')
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
          expect(env).to eq(Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_TRACE_ID => '90000',
            Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_PARENT_ID => '100000',
            Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_ORIGIN => 'synthetics')
        end
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
      let(:env) do
        { env_header(Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_TRACE_ID) => '10000',
          env_header(Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_PARENT_ID) => '20000' }
      end

      it { expect(digest.span_id).to eq(20000) }
      it { expect(digest.trace_id).to eq(10000) }
      it { expect(digest.trace_origin).to be nil }
      it { expect(digest.trace_sampling_priority).to be nil }

      context 'with sampling priority' do
        let(:env) do
          { env_header(Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_TRACE_ID) => '10000',
            env_header(Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_PARENT_ID) => '20000',
            env_header(Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_SAMPLING_PRIORITY) => '1' }
        end

        it { expect(digest.span_id).to eq(20000) }
        it { expect(digest.trace_id).to eq(10000) }
        it { expect(digest.trace_origin).to be nil }
        it { expect(digest.trace_sampling_priority).to eq(1) }

        context 'with origin' do
          let(:env) do
            { env_header(Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_TRACE_ID) => '10000',
              env_header(Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_PARENT_ID) => '20000',
              env_header(Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_SAMPLING_PRIORITY) => '1',
              env_header(Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_ORIGIN) => 'synthetics' }
          end

          it { expect(digest.span_id).to eq(20000) }
          it { expect(digest.trace_id).to eq(10000) }
          it { expect(digest.trace_origin).to eq('synthetics') }
          it { expect(digest.trace_sampling_priority).to eq(1) }
        end
      end

      context 'with origin' do
        let(:env) do
          { env_header(Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_TRACE_ID) => '10000',
            env_header(Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_PARENT_ID) => '20000',
            env_header(Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_ORIGIN) => 'synthetics' }
        end

        it { expect(digest.span_id).to eq(20000) }
        it { expect(digest.trace_id).to eq(10000) }
        it { expect(digest.trace_origin).to eq('synthetics') }
        it { expect(digest.trace_sampling_priority).to be nil }
      end
    end

    context 'with span_id' do
      let(:env) { { env_header(Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_PARENT_ID) => '10000' } }

      it { is_expected.to be nil }
    end

    context 'with origin' do
      let(:env) { { env_header(Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_ORIGIN) => 'synthetics' } }

      it { is_expected.to be nil }
    end

    context 'with sampling priority' do
      let(:env) { { env_header(Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_SAMPLING_PRIORITY) => '1' } }

      it { is_expected.to be nil }
    end

    context 'with trace_id' do
      let(:env) { { env_header(Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_TRACE_ID) => '10000' } }

      it { is_expected.to be nil }

      context 'with synthetics origin' do
        let(:env) do
          { env_header(Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_TRACE_ID) => '10000',
            env_header(Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_ORIGIN) => 'synthetics' }
        end

        it { expect(digest.span_id).to be nil }
        it { expect(digest.trace_id).to eq(10000) }
        it { expect(digest.trace_origin).to eq('synthetics') }
        it { expect(digest.trace_sampling_priority).to be nil }
      end

      context 'with non-synthetics origin' do
        let(:env) do
          { env_header(Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_TRACE_ID) => '10000',
            env_header(Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_ORIGIN) => 'custom-origin' }
        end

        it { expect(digest.span_id).to be nil }
        it { expect(digest.trace_id).to eq(10000) }
        it { expect(digest.trace_origin).to eq('custom-origin') }
        it { expect(digest.trace_sampling_priority).to be nil }
      end
    end
  end
end
