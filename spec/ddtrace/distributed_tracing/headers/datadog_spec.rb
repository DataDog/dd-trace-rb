require 'spec_helper'

require 'ddtrace'
require 'ddtrace/context'
require 'ddtrace/ext/distributed'
require 'ddtrace/distributed_tracing/headers/datadog'

RSpec.describe Datadog::DistributedTracing::Headers::Datadog do
  let(:context) { Datadog.Context.new }

  # Helper to format env header keys
  def env_header(name)
    "http-#{name}".upcase!.tr('-', '_')
  end

  context '#inject!' do
    subject(:env) { {} }
    before(:each) { described_class.inject!(context, env) }

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
        is_expected.to eq(Datadog::Ext::DistributedTracing::HTTP_HEADER_TRACE_ID => '10000',
                          Datadog::Ext::DistributedTracing::HTTP_HEADER_PARENT_ID => '20000')
      end

      context 'with sampling priority' do
        let(:context) do
          Datadog::Context.new(trace_id: 50000,
                               span_id: 60000,
                               sampling_priority: 1)
        end

        it do
          is_expected.to eq(Datadog::Ext::DistributedTracing::HTTP_HEADER_TRACE_ID => '50000',
                            Datadog::Ext::DistributedTracing::HTTP_HEADER_PARENT_ID => '60000',
                            Datadog::Ext::DistributedTracing::HTTP_HEADER_SAMPLING_PRIORITY => '1')
        end

        context 'with origin' do
          let(:context) do
            Datadog::Context.new(trace_id: 70000,
                                 span_id: 80000,
                                 sampling_priority: 1,
                                 origin: 'synthetics')
          end

          it do
            is_expected.to eq(Datadog::Ext::DistributedTracing::HTTP_HEADER_TRACE_ID => '70000',
                              Datadog::Ext::DistributedTracing::HTTP_HEADER_PARENT_ID => '80000',
                              Datadog::Ext::DistributedTracing::HTTP_HEADER_SAMPLING_PRIORITY => '1',
                              Datadog::Ext::DistributedTracing::HTTP_HEADER_ORIGIN => 'synthetics')
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
          is_expected.to eq(Datadog::Ext::DistributedTracing::HTTP_HEADER_TRACE_ID => '90000',
                            Datadog::Ext::DistributedTracing::HTTP_HEADER_PARENT_ID => '100000',
                            Datadog::Ext::DistributedTracing::HTTP_HEADER_ORIGIN => 'synthetics')
        end
      end
    end
  end

  context '#extract' do
    subject(:context) { described_class.extract(env) }
    let(:env) { {} }

    context 'with empty env' do
      it { is_expected.to be nil }
    end

    context 'with trace_id and span_id' do
      let(:env) do
        { env_header(Datadog::Ext::DistributedTracing::HTTP_HEADER_TRACE_ID) => '10000',
          env_header(Datadog::Ext::DistributedTracing::HTTP_HEADER_PARENT_ID) => '20000' }
      end

      it { expect(context.trace_id).to eq(10000) }
      it { expect(context.span_id).to eq(20000) }
      it { expect(context.sampling_priority).to be nil }
      it { expect(context.origin).to be nil }

      context 'with sampling priority' do
        let(:env) do
          { env_header(Datadog::Ext::DistributedTracing::HTTP_HEADER_TRACE_ID) => '10000',
            env_header(Datadog::Ext::DistributedTracing::HTTP_HEADER_PARENT_ID) => '20000',
            env_header(Datadog::Ext::DistributedTracing::HTTP_HEADER_SAMPLING_PRIORITY) => '1' }
        end

        it { expect(context.trace_id).to eq(10000) }
        it { expect(context.span_id).to eq(20000) }
        it { expect(context.sampling_priority).to eq(1) }
        it { expect(context.origin).to be nil }

        context 'with origin' do
          let(:env) do
            { env_header(Datadog::Ext::DistributedTracing::HTTP_HEADER_TRACE_ID) => '10000',
              env_header(Datadog::Ext::DistributedTracing::HTTP_HEADER_PARENT_ID) => '20000',
              env_header(Datadog::Ext::DistributedTracing::HTTP_HEADER_SAMPLING_PRIORITY) => '1',
              env_header(Datadog::Ext::DistributedTracing::HTTP_HEADER_ORIGIN) => 'synthetics' }
          end

          it { expect(context.trace_id).to eq(10000) }
          it { expect(context.span_id).to eq(20000) }
          it { expect(context.sampling_priority).to eq(1) }
          it { expect(context.origin).to eq('synthetics') }
        end
      end

      context 'with origin' do
        let(:env) do
          { env_header(Datadog::Ext::DistributedTracing::HTTP_HEADER_TRACE_ID) => '10000',
            env_header(Datadog::Ext::DistributedTracing::HTTP_HEADER_PARENT_ID) => '20000',
            env_header(Datadog::Ext::DistributedTracing::HTTP_HEADER_ORIGIN) => 'synthetics' }
        end

        it { expect(context.trace_id).to eq(10000) }
        it { expect(context.span_id).to eq(20000) }
        it { expect(context.sampling_priority).to be nil }
        it { expect(context.origin).to eq('synthetics') }
      end
    end

    context 'with span_id' do
      let(:env) { { env_header(Datadog::Ext::DistributedTracing::HTTP_HEADER_PARENT_ID) => '10000' } }
      it { is_expected.to be nil }
    end

    context 'with origin' do
      let(:env) { { env_header(Datadog::Ext::DistributedTracing::HTTP_HEADER_ORIGIN) => 'synthetics' } }
      it { is_expected.to be nil }
    end

    context 'with sampling priority' do
      let(:env) { { env_header(Datadog::Ext::DistributedTracing::HTTP_HEADER_SAMPLING_PRIORITY) => '1' } }
      it { is_expected.to be nil }
    end

    context 'with trace_id' do
      let(:env) { { env_header(Datadog::Ext::DistributedTracing::HTTP_HEADER_TRACE_ID) => '10000' } }
      it { is_expected.to be nil }

      context 'with synthetics origin' do
        let(:env) do
          { env_header(Datadog::Ext::DistributedTracing::HTTP_HEADER_TRACE_ID) => '10000',
            env_header(Datadog::Ext::DistributedTracing::HTTP_HEADER_ORIGIN) => 'synthetics' }
        end

        it { expect(context.trace_id).to eq(10000) }
        it { expect(context.span_id).to be nil }
        it { expect(context.sampling_priority).to be nil }
        it { expect(context.origin).to eq('synthetics') }
      end

      context 'with non-synthetics origin' do
        let(:env) do
          { env_header(Datadog::Ext::DistributedTracing::HTTP_HEADER_TRACE_ID) => '10000',
            env_header(Datadog::Ext::DistributedTracing::HTTP_HEADER_ORIGIN) => 'custom-origin' }
        end

        it { expect(context.trace_id).to eq(10000) }
        it { expect(context.span_id).to be nil }
        it { expect(context.sampling_priority).to be nil }
        it { expect(context.origin).to eq('custom-origin') }
      end
    end
  end
end
