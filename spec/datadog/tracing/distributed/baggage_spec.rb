require 'spec_helper'

require 'datadog/tracing/distributed/datadog'
require 'datadog/tracing/trace_digest'
require 'datadog/tracing/utils'

RSpec.shared_examples 'Baggage distributed format' do
  let(:propagation_style_inject) { %w[baggage] }
  let(:propagation_style_extract) { %w[baggage] }

  let(:prepare_key) { defined?(super) ? super() : proc { |key| key } }

  describe '#inject!' do
    subject(:inject!) { propagation.inject!(digest, data) }
    let(:data) { {} }

    context 'with nil digest' do
      let(:digest) { nil }
      it { is_expected.to be nil }
    end

    context 'with TraceDigest' do
      let(:digest) do
        Datadog::Tracing::TraceDigest.new(
          baggage: { 'key' => 'value' },
        )
      end

      it do
        inject!
        expect(data).to eq(
          'baggage' => 'key=value',
        )
      end

      context 'with multiple key value' do
        let(:digest) do
          Datadog::Tracing::TraceDigest.new(
            baggage: { 'key' => 'value', 'key2' => 'value2' },
          )
        end

        it do
          inject!
          expect(data).to eq(
            'baggage' => 'key=value,key2=value2',
          )
        end
      end

      context 'with special allowed characters' do
        let(:digest) do
          Datadog::Tracing::TraceDigest.new(
            baggage: { 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#$&\'*+-.^_`|~' =>
            'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#$&\'()*+-./:<>?@[]^_`{|}~',
                       'key2' => 'value2' },
          )
        end

        it do
          inject!
          expect(data).to eq(
            'baggage' => 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#$&\'*+-.^' \
            '_`|~=ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#$&\'()*+-./:<>?@[]^_`{|}~,key2=value2',
          )
        end
      end

      context 'with special disallowed characters' do
        let(:digest) do
          Datadog::Tracing::TraceDigest.new(
            baggage: { 'key with=spacesand%' => 'value with=spaces' },
          )
        end

        it do
          inject!
          expect(data).to eq(
            'baggage' => 'key%20with%3Dspacesand%25=value%20with%3Dspaces',
          )
        end
      end

      context 'with other special disallowed characters' do
        let(:digest) do
          Datadog::Tracing::TraceDigest.new(
            baggage: { 'userId' => 'Amélie' },
          )
        end

        it do
          inject!
          expect(data).to eq(
            'baggage' => 'userId=Am%C3%A9lie',
          )
        end
      end

      context 'when baggage size exceeds maximum items' do
        let(:digest) do
          Datadog::Tracing::TraceDigest.new(
            baggage: (1..(Datadog::Tracing::Distributed::Baggage::DD_TRACE_BAGGAGE_MAX_ITEMS + 1)).map do |i|
              ["key#{i}", "value#{i}"]
            end.to_h
          )
        end

        it 'logs a warning and stops injecting excess items' do
          expect(Datadog.logger).to receive(:warn).with('Baggage item limit exceeded, dropping excess items')
          inject!
          expect(data['baggage'].split(',').size).to eq(Datadog::Tracing::Distributed::Baggage::DD_TRACE_BAGGAGE_MAX_ITEMS)
        end
      end

      context 'when baggage size exceeds maximum bytes' do
        let(:digest) do
          Datadog::Tracing::TraceDigest.new(
            baggage: { 'key1' => 'value1',
                       'key' => 'a' * (Datadog::Tracing::Distributed::Baggage::DD_TRACE_BAGGAGE_MAX_BYTES + 1) }
          )
        end

        it 'logs a warning and stops injecting excess items' do
          expect(Datadog.logger).to receive(:warn).with('Baggage header size exceeded, dropping excess items')
          inject!
          expect(data['baggage']).to eq('key1=value1')
        end
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

    context 'single key value' do
      let(:data) do
        { prepare_key['baggage'] => 'key=value' }
      end

      it { expect(digest.baggage).to eq({ 'key' => 'value' }) }
    end

    context 'multiple key value' do
      let(:data) do
        { prepare_key['baggage'] => 'key=value,key2=value2' }
      end

      it { expect(digest.baggage).to eq({ 'key' => 'value', 'key2' => 'value2' }) }
    end

    context 'with special allowed characters' do
      let(:data) do
        { prepare_key['baggage'] => '&\'*`|~=$&\'()*,key2=value2' }
      end

      it {
        expect(digest.baggage).to eq({ '&\'*`|~' => '$&\'()*', 'key2' => 'value2' })
      }
    end

    context 'with special disallowed characters and trimming whitespace on ends' do
      let(:data) do
        { prepare_key['baggage'] => ' key%20with%3Dspacesand%25 = value%20with%3Dspaces , key2=value2' }
      end

      it { expect(digest.baggage).to eq({ 'key with=spacesand%' => 'value with=spaces', 'key2' => 'value2' }) }
    end
  end
end

RSpec.describe Datadog::Tracing::Distributed::Baggage do
  subject(:propagation) { described_class.new(fetcher: fetcher_class) }
  let(:fetcher_class) { Datadog::Tracing::Distributed::Fetcher }

  it_behaves_like 'Baggage distributed format'
end
