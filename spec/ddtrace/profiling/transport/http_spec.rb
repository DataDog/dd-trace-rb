require 'spec_helper'
require 'securerandom'

require 'ddtrace/profiling/transport/http'
require 'ddtrace/profiling/transport/http/client'

RSpec.describe Datadog::Profiling::Transport::HTTP do
  describe '::new' do
    context 'given a block' do
      subject(:new_http) { described_class.new(&block) }
      let(:block) { proc {} }

      let(:builder) { instance_double(Datadog::Profiling::Transport::HTTP::Builder) }
      let(:client) { instance_double(Datadog::Profiling::Transport::HTTP::Client) }

      before do
        expect(Datadog::Transport::HTTP::Builder).to receive(:new) do |&blk|
          expect(blk).to be block
          builder
        end

        expect(builder).to receive(:to_transport)
          .and_return(client)
      end

      it { is_expected.to be client }
    end
  end

  describe '::default' do
    subject(:default) { described_class.default }

    shared_examples_for 'default HTTP agent transport' do
      it 'returns default configuration' do
        is_expected.to be_a_kind_of(Datadog::Profiling::Transport::HTTP::Client)
        expect(default.api.spec).to eq(
          Datadog::Profiling::Transport::HTTP::API.agent_defaults[Datadog::Profiling::Transport::HTTP::API::V1]
        )

        expect(default.api).to be_a_kind_of(Datadog::Profiling::Transport::HTTP::API::Instance)
        expect(default.api.adapter).to be_a_kind_of(Datadog::Transport::HTTP::Adapters::Net)
        expect(default.api.adapter.hostname).to eq(described_class.default_hostname)
        expect(default.api.adapter.port).to eq(described_class.default_port)
        expect(default.api.adapter.timeout).to eq(30)
        expect(default.api.adapter.ssl).to be false
        expect(default.api.headers).to include(described_class.default_headers)
        expect(default.api.headers).to_not include(Datadog::Ext::Transport::HTTP::HEADER_DD_API_KEY)
      end
    end

    it_behaves_like 'default HTTP agent transport'

    context 'when given options' do
      subject(:default) { described_class.default(options) }

      context 'that are empty' do
        let(:options) { {} }
        it_behaves_like 'default HTTP agent transport'
      end

      context 'that specify site and API key' do
        let(:options) { { site: site, api_key: api_key } }
        let(:site) { 'test.datadoghq.com' }
        let(:api_key) { SecureRandom.uuid }

        it 'returns a transport configured for agentless' do
          expected_host = URI(format(Datadog::Ext::Profiling::Transport::HTTP::URI_TEMPLATE_DD_API, site)).host
          expect(default.api.adapter).to be_a_kind_of(Datadog::Transport::HTTP::Adapters::Net)
          expect(default.api.adapter.hostname).to eq(expected_host)
          expect(default.api.adapter.port).to eq(443)
          expect(default.api.adapter.ssl).to be true
          expect(default.api.headers).to include(Datadog::Ext::Transport::HTTP::HEADER_DD_API_KEY => api_key)
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
          expect(default.api.adapter).to be_a_kind_of(Datadog::Transport::HTTP::Adapters::Net)
          expect(default.api.adapter.hostname).to eq(hostname)
          expect(default.api.adapter.port).to eq(port)
          expect(default.api.adapter.timeout).to be(timeout)
          expect(default.api.adapter.ssl).to be true
        end
      end

      context 'that specify an API version' do
        let(:options) { { api_version: api_version } }

        context 'that is not defined' do
          let(:api_version) { double('non-existent API') }
          it { expect { default }.to raise_error(Datadog::Transport::HTTP::Builder::UnknownApiError) }
        end
      end

      context 'that specify headers' do
        let(:options) { { headers: headers } }
        let(:headers) { { 'Test-Header' => 'foo' } }

        it do
          expect(default.api.headers).to include(described_class.default_headers)
          expect(default.api.headers).to include(headers)
        end
      end
    end

    context 'when given a block' do
      it do
        expect { |b| described_class.default(&b) }.to yield_with_args(
          kind_of(Datadog::Profiling::Transport::HTTP::Builder)
        )
      end
    end
  end

  describe '::default_headers' do
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

  describe '::default_adapter' do
    subject(:default_adapter) { described_class.default_adapter }
    it { is_expected.to be(:net_http) }
  end

  describe '::default_hostname' do
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
    end
  end

  describe '::default_port' do
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
    end
  end
end
