require 'spec_helper'

require 'ddtrace/transport/http'
require 'uri'

RSpec.describe Datadog::Transport::HTTP do
  describe '.new' do
    context 'given a block' do
      subject(:new_http) { described_class.new(&block) }
      let(:block) { proc {} }

      let(:builder) { instance_double(Datadog::Transport::HTTP::Builder) }
      let(:transport) { instance_double(Datadog::Transport::Traces::Transport) }

      before do
        expect(Datadog::Transport::HTTP::Builder).to receive(:new) do |&blk|
          expect(blk).to be block
          builder
        end

        expect(builder).to receive(:to_transport)
          .and_return(transport)
      end

      it { is_expected.to be transport }
    end
  end

  describe '.default' do
    subject(:default) { described_class.default }

    it 'returns an HTTP transport with default configuration' do
      is_expected.to be_a_kind_of(Datadog::Transport::Traces::Transport)
      expect(default.current_api_id).to eq(Datadog::Transport::HTTP::API::V4)

      expect(default.apis.keys).to eq(
        [
          Datadog::Transport::HTTP::API::V4,
          Datadog::Transport::HTTP::API::V3,
          Datadog::Transport::HTTP::API::V2
        ]
      )

      default.apis.each do |_key, api|
        expect(api).to be_a_kind_of(Datadog::Transport::HTTP::API::Instance)
        expect(api.adapter).to be_a_kind_of(Datadog::Transport::HTTP::Adapters::Net)
        expect(api.adapter.hostname).to eq(described_class.default_hostname)
        expect(api.adapter.port).to eq(described_class.default_port)
        expect(api.adapter.timeout).to eq(1)
        expect(api.adapter.ssl).to be false
        expect(api.headers).to include(described_class.default_headers)
      end
    end

    context 'when given options' do
      subject(:default) { described_class.default(options) }

      context 'that are empty' do
        let(:options) { {} }

        it 'returns an HTTP transport with default configuration' do
          is_expected.to be_a_kind_of(Datadog::Transport::Traces::Transport)
          expect(default.current_api_id).to eq(Datadog::Transport::HTTP::API::V4)

          expect(default.apis.keys).to eq(
            [
              Datadog::Transport::HTTP::API::V4,
              Datadog::Transport::HTTP::API::V3,
              Datadog::Transport::HTTP::API::V2
            ]
          )

          default.apis.each do |_key, api|
            expect(api).to be_a_kind_of(Datadog::Transport::HTTP::API::Instance)
            expect(api.adapter).to be_a_kind_of(Datadog::Transport::HTTP::Adapters::Net)
            expect(api.adapter.hostname).to eq(described_class.default_hostname)
            expect(api.adapter.port).to eq(described_class.default_port)
            expect(api.adapter.timeout).to eq(1)
            expect(api.adapter.ssl).to be false
            expect(api.headers).to include(described_class.default_headers)
          end
        end
      end

      context 'that specify host, port, timeout or ssl' do
        let(:options) do
          {
            hostname: hostname,
            port: port,
            timeout: timeout,
            ssl: ssl
          }
        end

        let(:hostname) { double('hostname') }
        let(:port) { double('port') }
        let(:timeout) { double('timeout') }
        let(:ssl) { true }

        it 'returns a transport with provided options' do
          default.apis.each do |_key, api|
            expect(api.adapter).to be_a_kind_of(Datadog::Transport::HTTP::Adapters::Net)
            expect(api.adapter.hostname).to eq(hostname)
            expect(api.adapter.port).to eq(port)
            expect(api.adapter.timeout).to be(timeout)
            expect(api.adapter.ssl).to be true
          end
        end
      end

      context 'that specify an API version' do
        let(:options) { { api_version: api_version } }

        context 'that is defined' do
          let(:api_version) { Datadog::Transport::HTTP::API::V2 }
          it { expect(default.current_api_id).to eq(api_version) }
        end

        context 'that is not defined' do
          let(:api_version) { double('non-existent API') }
          it { expect { default }.to raise_error(Datadog::Transport::HTTP::Builder::UnknownApiError) }
        end
      end

      context 'that specify headers' do
        let(:options) { { headers: headers } }
        let(:headers) { { 'Test-Header' => 'foo' } }

        it do
          default.apis.each do |_key, api|
            expect(api.headers).to include(described_class.default_headers)
            expect(api.headers).to include(headers)
          end
        end
      end
    end

    context 'when given a block' do
      it do
        expect { |b| described_class.default(&b) }.to yield_with_args(
          kind_of(Datadog::Transport::HTTP::Builder)
        )
      end
    end
  end

  describe '.default_headers' do
    subject(:default_headers) { described_class.default_headers }

    it do
      is_expected.to include(
        Datadog::Ext::Transport::HTTP::HEADER_META_LANG => Datadog::Ext::Runtime::LANG,
        Datadog::Ext::Transport::HTTP::HEADER_META_LANG_VERSION => Datadog::Ext::Runtime::LANG_VERSION,
        Datadog::Ext::Transport::HTTP::HEADER_META_LANG_INTERPRETER => Datadog::Ext::Runtime::LANG_INTERPRETER,
        Datadog::Ext::Transport::HTTP::HEADER_META_TRACER_VERSION => Datadog::Ext::Runtime::TRACER_VERSION
      )
    end

    context 'when Runtime::Container.container_id' do
      before { expect(Datadog::Runtime::Container).to receive(:container_id).and_return(container_id) }

      context 'is not nil' do
        let(:container_id) { '3726184226f5d3147c25fdeab5b60097e378e8a720503a5e19ecfdf29f869860' }
        it { is_expected.to include(Datadog::Ext::Transport::HTTP::HEADER_CONTAINER_ID => container_id) }
      end

      context 'is nil' do
        let(:container_id) { nil }
        it { is_expected.to_not include(Datadog::Ext::Transport::HTTP::HEADER_CONTAINER_ID) }
      end
    end
  end

  describe '.default_adapter' do
    subject(:default_adapter) { described_class.default_adapter }
    it { is_expected.to be(:net_http) }
  end

  describe '.default_hostname' do
    subject(:default_hostname) { described_class.default_hostname }

    context 'when environment variable is' do
      context 'set' do
        let(:value) { 'my-hostname' }

        around do |example|
          ClimateControl.modify(Datadog::Ext::Transport::HTTP::ENV_DEFAULT_HOST => value) do
            example.run
          end
        end

        it { is_expected.to eq(value) }
      end

      context 'not set' do
        around do |example|
          ClimateControl.modify(Datadog::Ext::Transport::HTTP::ENV_DEFAULT_HOST => nil) do
            example.run
          end
        end

        it { is_expected.to eq(Datadog::Ext::Transport::HTTP::DEFAULT_HOST) }
      end

      context 'set via url' do
        let(:value) { 'http://my-hostname:8125' }

        around do |example|
          ClimateControl.modify(Datadog::Ext::Transport::HTTP::ENV_DEFAULT_URL => value) do
            example.run
          end
        end

        it { is_expected.to eq(URI.parse(value).hostname) }
      end
    end
  end

  describe '.default_port' do
    subject(:default_port) { described_class.default_port }

    context 'when environment variable is' do
      context 'set' do
        let(:value) { '1234' }

        around do |example|
          ClimateControl.modify(Datadog::Ext::Transport::HTTP::ENV_DEFAULT_PORT => value) do
            example.run
          end
        end

        it { is_expected.to eq(value.to_i) }
      end

      context 'not set' do
        around do |example|
          ClimateControl.modify(Datadog::Ext::Transport::HTTP::ENV_DEFAULT_PORT => nil) do
            example.run
          end
        end

        it { is_expected.to eq(Datadog::Ext::Transport::HTTP::DEFAULT_PORT) }
      end

      context 'set via url' do
        let(:value) { 'http://my-hostname:8125' }

        around do |example|
          ClimateControl.modify(Datadog::Ext::Transport::HTTP::ENV_DEFAULT_URL => value) do
            example.run
          end
        end

        it { is_expected.to eq(URI.parse(value).port) }
      end
    end
  end
end
