require 'spec_helper'

require 'ddtrace/transport/http'

RSpec.describe Datadog::Transport::HTTP do
  describe '.new' do
    context 'given a block' do
      subject(:new_http) { described_class.new(&block) }
      let(:block) { proc {} }

      let(:builder) { instance_double(Datadog::Transport::HTTP::Builder) }
      let(:client) { instance_double(Datadog::Transport::HTTP::Client) }

      before do
        expect(Datadog::Transport::HTTP::Builder).to receive(:new) do |&blk|
          expect(blk).to be block
          builder
        end

        expect(builder).to receive(:to_client)
          .and_return(client)
      end

      it { is_expected.to be client }
    end
  end

  describe '.default' do
    subject(:default) { described_class.default }

    it 'returns an HTTP client with default configuration' do
      is_expected.to be_a_kind_of(Datadog::Transport::HTTP::Client)
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
        expect(api.headers).to eq(described_class::DEFAULT_HEADERS)
      end
    end

    context 'when given options' do
      subject(:default) { described_class.default(options) }

      context 'that are empty' do
        let(:options) { {} }

        it 'returns an HTTP client with default configuration' do
          is_expected.to be_a_kind_of(Datadog::Transport::HTTP::Client)
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
            expect(api.headers).to eq(described_class::DEFAULT_HEADERS)
          end
        end
      end

      context 'that specify hostname and port' do
        let(:options) { { hostname: hostname, port: port } }
        let(:hostname) { double('hostname') }
        let(:port) { double('port') }

        it 'returns an HTTP client with default configuration' do
          default.apis.each do |_key, api|
            expect(api.adapter).to be_a_kind_of(Datadog::Transport::HTTP::Adapters::Net)
            expect(api.adapter.hostname).to eq(hostname)
            expect(api.adapter.port).to eq(port)
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
            expect(api.headers).to include(described_class::DEFAULT_HEADERS)
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
    end
  end
end
