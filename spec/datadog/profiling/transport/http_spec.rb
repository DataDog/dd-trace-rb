# typed: false

require 'spec_helper'
require 'securerandom'

require 'datadog/core/configuration/agent_settings_resolver'
require 'datadog/profiling/transport/http'
require 'datadog/profiling/transport/http/builder'
require 'datadog/profiling/transport/http/client'
require 'ddtrace/transport/ext'
require 'ddtrace/transport/http/adapters/net'

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
    subject(:default) { described_class.default(profiling_upload_timeout_seconds: timeout_seconds, **options) }

    let(:timeout_seconds) { double('Timeout in seconds') }
    let(:options) { { agent_settings: agent_settings } }

    let(:agent_settings) do
      Datadog::Core::Configuration::AgentSettingsResolver::AgentSettings.new(
        adapter: adapter,
        hostname: hostname,
        port: port,
        ssl: ssl,
        uds_path: uds_path,
        timeout_seconds: nil,
        deprecated_for_removal_transport_configuration_proc: deprecated_for_removal_transport_configuration_proc,
      )
    end
    let(:adapter) { :net_http }
    let(:hostname) { double('hostname') }
    let(:port) { double('port') }
    let(:profiling_upload_timeout_seconds) { double('timeout') }
    let(:ssl) { true }
    let(:uds_path) { double('uds_path') }
    let(:deprecated_for_removal_transport_configuration_proc) { nil }

    it 'returns a transport with provided options configured for agent mode' do
      expect(default.api.adapter).to be_a_kind_of(Datadog::Transport::HTTP::Adapters::Net)
      expect(default.api.adapter.hostname).to eq(hostname)
      expect(default.api.adapter.port).to eq(port)
      expect(default.api.adapter.timeout).to be timeout_seconds
      expect(default.api.adapter.ssl).to be true
      expect(default.api.headers).to include(described_class.default_headers)
      expect(default.api.headers).to_not include(Datadog::Transport::Ext::HTTP::HEADER_DD_API_KEY)
    end

    context 'when agent_settings has a deprecated_for_removal_transport_configuration_proc' do
      let(:deprecated_for_removal_transport_configuration_proc) { proc {} }

      it 'calls the deprecated_for_removal_transport_configuration_proc with the transport builder' do
        expect(deprecated_for_removal_transport_configuration_proc).to \
          receive(:call).with(an_instance_of(Datadog::Profiling::Transport::HTTP::Builder))

        default
      end
    end

    context 'when called with a site and api' do
      let(:options) do
        { agent_settings: double('agent_settings which should not be used'), site: site, api_key: api_key }
      end

      let(:site) { 'test.datadoghq.com' }
      let(:api_key) { SecureRandom.uuid }

      context 'when DD_PROFILING_AGENTLESS environment variable is set to "true"' do
        around do |example|
          ClimateControl.modify('DD_PROFILING_AGENTLESS' => 'true') do
            example.run
          end
        end

        it 'returns a transport configured for agentless' do
          expected_host = URI(format(Datadog::Profiling::OldExt::Transport::HTTP::URI_TEMPLATE_DD_API, site)).host
          expect(default.api.adapter).to be_a_kind_of(Datadog::Transport::HTTP::Adapters::Net)
          expect(default.api.adapter.hostname).to eq(expected_host)
          expect(default.api.adapter.port).to eq(443)
          expect(default.api.adapter.timeout).to be timeout_seconds
          expect(default.api.adapter.ssl).to be true
          expect(default.api.headers).to include(described_class.default_headers)
          expect(default.api.headers).to include(Datadog::Transport::Ext::HTTP::HEADER_DD_API_KEY => api_key)
        end
      end

      context 'when agentless_allowed is true' do
        let(:options) { { **super(), agentless_allowed: true } }

        it 'returns a transport configured for agentless' do
          expected_host = URI(format(Datadog::Profiling::OldExt::Transport::HTTP::URI_TEMPLATE_DD_API, site)).host
          expect(default.api.adapter).to be_a_kind_of(Datadog::Transport::HTTP::Adapters::Net)
          expect(default.api.adapter.hostname).to eq(expected_host)
          expect(default.api.adapter.port).to eq(443)
          expect(default.api.adapter.timeout).to be timeout_seconds
          expect(default.api.adapter.ssl).to be true
          expect(default.api.headers).to include(described_class.default_headers)
          expect(default.api.headers).to include(Datadog::Transport::Ext::HTTP::HEADER_DD_API_KEY => api_key)
        end
      end

      ['false', nil].each do |environment_value|
        context "when DD_PROFILING_AGENTLESS environment variable is set to #{environment_value.inspect}" do
          let(:options) { { **super(), agent_settings: agent_settings } }

          around do |example|
            ClimateControl.modify('DD_PROFILING_AGENTLESS' => environment_value) do
              example.run
            end
          end

          it 'returns a transport configured for agent mode' do
            expect(default.api.adapter.hostname).to eq(hostname)
          end
        end
      end
    end
  end

  describe '::default_headers' do
    subject(:default_headers) { described_class.default_headers }

    it do
      is_expected.to include(
        Datadog::Transport::Ext::HTTP::HEADER_META_LANG => Datadog::Core::Environment::Ext::LANG,
        Datadog::Transport::Ext::HTTP::HEADER_META_LANG_VERSION => Datadog::Core::Environment::Ext::LANG_VERSION,
        Datadog::Transport::Ext::HTTP::HEADER_META_LANG_INTERPRETER => Datadog::Core::Environment::Ext::LANG_INTERPRETER,
        Datadog::Transport::Ext::HTTP::HEADER_META_TRACER_VERSION => Datadog::Core::Environment::Ext::TRACER_VERSION
      )
    end

    context 'when Core::Environment::Container.container_id' do
      before { expect(Datadog::Core::Environment::Container).to receive(:container_id).and_return(container_id) }

      context 'is not nil' do
        let(:container_id) { '3726184226f5d3147c25fdeab5b60097e378e8a720503a5e19ecfdf29f869860' }

        it { is_expected.to include(Datadog::Transport::Ext::HTTP::HEADER_CONTAINER_ID => container_id) }
      end

      context 'is nil' do
        let(:container_id) { nil }

        it { is_expected.to_not include(Datadog::Transport::Ext::HTTP::HEADER_CONTAINER_ID) }
      end
    end
  end
end
