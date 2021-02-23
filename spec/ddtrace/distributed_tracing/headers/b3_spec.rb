require 'spec_helper'

require 'ddtrace'
require 'ddtrace/context'
require 'ddtrace/ext/distributed'
require 'ddtrace/distributed_tracing/headers/b3'

RSpec.describe Datadog::DistributedTracing::Headers::B3 do
  let(:context) { Datadog.Context.new }

  # Helper to format env header keys
  def env_header(name)
    "http-#{name}".upcase!.tr('-', '_')
  end

  describe '#inject!' do
    subject(:env) { {} }

    before { described_class.inject!(context, env) }

    context 'with nil context' do
      let(:context) { nil }

      it { is_expected.to eq({}) }
    end

    context 'with trace_id and span_id' do
      let(:context) do
        Datadog::Context.new(trace_id: 10000,
                             span_id: 20000)
      end

      it do
        is_expected.to eq(Datadog::Ext::DistributedTracing::B3_HEADER_TRACE_ID => 10000.to_s(16),
                          Datadog::Ext::DistributedTracing::B3_HEADER_SPAN_ID => 20000.to_s(16))
      end

      [
        [-1, 0],
        [0, 0],
        [1, 1],
        [2, 1]
      ].each do |value, expected|
        context "with sampling priority #{value}" do
          let(:context) do
            Datadog::Context.new(trace_id: 50000,
                                 span_id: 60000,
                                 sampling_priority: value)
          end

          it do
            is_expected.to eq(Datadog::Ext::DistributedTracing::B3_HEADER_TRACE_ID => 50000.to_s(16),
                              Datadog::Ext::DistributedTracing::B3_HEADER_SPAN_ID => 60000.to_s(16),
                              Datadog::Ext::DistributedTracing::B3_HEADER_SAMPLED => expected.to_s)
          end
        end
      end

      context 'with origin' do
        let(:context) do
          Datadog::Context.new(trace_id: 90000,
                               span_id: 100000,
                               origin: 'synthetics')
        end

        it do
          is_expected.to eq(Datadog::Ext::DistributedTracing::B3_HEADER_TRACE_ID => 90000.to_s(16),
                            Datadog::Ext::DistributedTracing::B3_HEADER_SPAN_ID => 100000.to_s(16))
        end
      end
    end
  end

  describe '#extract' do
    subject(:context) { described_class.extract(env) }

    let(:env) { {} }

    context 'with empty env' do
      it { is_expected.to be_nil }
    end

    context 'with trace_id and span_id' do
      let(:env) do
        { env_header(Datadog::Ext::DistributedTracing::B3_HEADER_TRACE_ID) => 10000.to_s(16),
          env_header(Datadog::Ext::DistributedTracing::B3_HEADER_SPAN_ID) => 20000.to_s(16) }
      end

      it { expect(context.trace_id).to eq(10000) }
      it { expect(context.span_id).to eq(20000) }
      it { expect(context.sampling_priority).to be_nil }
      it { expect(context.origin).to be_nil }

      context 'with sampling priority' do
        let(:env) do
          { env_header(Datadog::Ext::DistributedTracing::B3_HEADER_TRACE_ID) => 10000.to_s(16),
            env_header(Datadog::Ext::DistributedTracing::B3_HEADER_SPAN_ID) => 20000.to_s(16),
            env_header(Datadog::Ext::DistributedTracing::B3_HEADER_SAMPLED) => '1' }
        end

        it { expect(context.trace_id).to eq(10000) }
        it { expect(context.span_id).to eq(20000) }
        it { expect(context.sampling_priority).to eq(1) }
        it { expect(context.origin).to be_nil }
      end

      context 'with origin' do
        let(:env) do
          { env_header(Datadog::Ext::DistributedTracing::B3_HEADER_TRACE_ID) => 10000.to_s(16),
            env_header(Datadog::Ext::DistributedTracing::B3_HEADER_SPAN_ID) => 20000.to_s(16),
            env_header(Datadog::Ext::DistributedTracing::HTTP_HEADER_ORIGIN) => 'synthetics' }
        end

        it { expect(context.trace_id).to eq(10000) }
        it { expect(context.span_id).to eq(20000) }
        it { expect(context.sampling_priority).to be_nil }
        it { expect(context.origin).to be_nil }
      end
    end

    context 'with span_id' do
      let(:env) { { env_header(Datadog::Ext::DistributedTracing::B3_HEADER_SPAN_ID) => 10000.to_s(16) } }

      it { is_expected.to be_nil }
    end

    context 'with sampling priority' do
      let(:env) { { env_header(Datadog::Ext::DistributedTracing::B3_HEADER_SAMPLED) => '1' } }

      it { is_expected.to be_nil }
    end

    context 'with trace_id' do
      let(:env) { { env_header(Datadog::Ext::DistributedTracing::B3_HEADER_TRACE_ID) => 10000.to_s(16) } }

      it { is_expected.to be_nil }
    end
  end
end
