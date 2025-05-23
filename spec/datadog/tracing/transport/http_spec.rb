require 'spec_helper'

require 'datadog/tracing/transport/http'

RSpec.describe Datadog::Tracing::Transport::HTTP do
  let(:logger) { logger_allowing_debug }

  describe '.default' do
    subject(:default) { described_class.default(agent_settings: default_agent_settings, logger: logger) }
    let(:default_agent_settings) do
      Datadog::Core::Configuration::AgentSettingsResolver.call(
        Datadog::Core::Configuration::Settings.new,
        logger: nil,
      )
    end

    # This test changes based on the environment tests are running. We have other
    # tests around each specific environment scenario, while this one specifically
    # ensures that we are matching the default environment settings.
    it 'returns a transport with default configuration' do
      is_expected.to be_a_kind_of(Datadog::Tracing::Transport::Traces::Transport)
      expect(default.current_api_id).to eq(Datadog::Tracing::Transport::HTTP::API::V4)

      expect(default.apis.keys).to eq(
        [
          Datadog::Tracing::Transport::HTTP::API::V4,
          Datadog::Tracing::Transport::HTTP::API::V3,
        ]
      )

      default.apis.each_value do |api|
        expect(api).to be_a_kind_of(Datadog::Tracing::Transport::HTTP::Traces::API::Instance)
        expect(api.headers).to include(Datadog::Core::Transport::HTTP.default_headers)

        case default_agent_settings.adapter
        when :net_http
          expect(api.adapter).to be_a_kind_of(Datadog::Core::Transport::HTTP::Adapters::Net)
          expect(api.adapter.hostname).to eq(default_agent_settings.hostname)
          expect(api.adapter.port).to eq(default_agent_settings.port)
          expect(api.adapter.ssl).to be(default_agent_settings.ssl)
        when :unix
          expect(api.adapter).to be_a_kind_of(Datadog::Core::Transport::HTTP::Adapters::UnixSocket)
          expect(api.adapter.filepath).to eq(default_agent_settings.uds_path)
        else
          raise("Unknown default adapter: #{default_agent_settings.adapter}")
        end
      end
    end

    context 'when given an agent_settings' do
      subject(:default) { described_class.default(agent_settings: agent_settings, logger: logger, **options) }

      let(:options) { {} }

      let(:adapter) { :net_http }
      let(:ssl) { nil }
      let(:hostname) { nil }
      let(:port) { nil }
      let(:uds_path) { nil }
      let(:timeout_seconds) { nil }

      let(:agent_settings) do
        Datadog::Core::Configuration::AgentSettingsResolver::AgentSettings.new(
          adapter: adapter,
          ssl: ssl,
          hostname: hostname,
          port: port,
          uds_path: uds_path,
          timeout_seconds: timeout_seconds
        )
      end

      context 'that specifies host, port, timeout and ssl' do
        let(:hostname) { double('hostname') }
        let(:port) { double('port') }
        let(:timeout_seconds) { double('timeout') }
        let(:ssl) { true }

        it 'returns a transport with provided options' do
          default.apis.each_value do |api|
            expect(api.adapter).to be_a_kind_of(Datadog::Core::Transport::HTTP::Adapters::Net)
            expect(api.adapter.hostname).to eq(hostname)
            expect(api.adapter.port).to eq(port)
            expect(api.adapter.timeout).to be(timeout_seconds)
            expect(api.adapter.ssl).to be true
          end
        end
      end
    end

    context 'when given options' do
      subject(:default) { described_class.default(agent_settings: default_agent_settings, logger: logger, **options) }

      context 'that specify an API version' do
        let(:options) { { api_version: api_version } }

        context 'that is defined' do
          let(:api_version) { Datadog::Tracing::Transport::HTTP::API::V4 }

          it { expect(default.current_api_id).to eq(api_version) }
        end

        context 'that is not defined' do
          let(:api_version) { double('non-existent API') }

          it { expect { default }.to raise_error(Datadog::Core::Transport::HTTP::Builder::UnknownApiError) }
        end
      end

      context 'that specify headers' do
        let(:options) { { headers: headers } }
        let(:headers) { { 'Test-Header' => 'foo' } }

        it do
          default.apis.each_value do |api|
            expect(api.headers).to include(Datadog::Core::Transport::HTTP.default_headers)
            expect(api.headers).to include(headers)
          end
        end
      end
    end

    context 'when given a block' do
      it do
        expect do |b|
          described_class.default(agent_settings: default_agent_settings, logger: logger, &b)
        end.to yield_with_args(
          kind_of(Datadog::Core::Transport::HTTP::Builder)
        )
      end
    end
  end
end
