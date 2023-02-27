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
    let(:env_agent_settings) { described_class::DO_NOT_USE_ENVIRONMENT_AGENT_SETTINGS }

    # This test changes based on the environment tests are running. We have other
    # tests around each specific environment scenario, while this one specifically
    # ensures that we are matching the default environment settings.
    #
    # TODO: we should deprecate the use of DO_NOT_USE_ENVIRONMENT_AGENT_SETTINGS
    # and thus remove this test scenario.
    it 'returns a transport with default configuration' do
      is_expected.to be_a_kind_of(Datadog::Transport::Traces::Transport)
      expect(default.current_api_id).to eq(Datadog::Transport::HTTP::API::V4)

      expect(default.apis.keys).to eq(
        [
          Datadog::Transport::HTTP::API::V4,
          Datadog::Transport::HTTP::API::V3,
        ]
      )

      default.apis.each_value do |api|
        expect(api).to be_a_kind_of(Datadog::Transport::HTTP::API::Instance)
        expect(api.headers).to include(described_class.default_headers)

        case env_agent_settings.adapter
        when :net_http
          expect(api.adapter).to be_a_kind_of(Datadog::Transport::HTTP::Adapters::Net)
          expect(api.adapter.hostname).to eq(env_agent_settings.hostname)
          expect(api.adapter.port).to eq(env_agent_settings.port)
          expect(api.adapter.ssl).to be(env_agent_settings.ssl)
        when :unix
          expect(api.adapter).to be_a_kind_of(Datadog::Transport::HTTP::Adapters::UnixSocket)
          expect(api.adapter.filepath).to eq(env_agent_settings.uds_path)
        else
          raise("Unknown default adapter: #{env_agent_settings.adapter}")
        end
      end
    end

    context 'when given an agent_settings' do
      subject(:default) { described_class.default(agent_settings: agent_settings, **options) }

      let(:options) { {} }

      let(:adapter) { :net_http }
      let(:ssl) { nil }
      let(:hostname) { nil }
      let(:port) { nil }
      let(:uds_path) { nil }
      let(:timeout_seconds) { nil }
      let(:deprecated_for_removal_transport_configuration_proc) { nil }

      let(:agent_settings) do
        Datadog::Core::Configuration::AgentSettingsResolver::AgentSettings.new(
          adapter: adapter,
          ssl: ssl,
          hostname: hostname,
          port: port,
          uds_path: uds_path,
          timeout_seconds: timeout_seconds,
          deprecated_for_removal_transport_configuration_proc: deprecated_for_removal_transport_configuration_proc,
        )
      end

      context 'that specifies host, port, timeout and ssl' do
        let(:hostname) { double('hostname') }
        let(:port) { double('port') }
        let(:timeout_seconds) { double('timeout') }
        let(:ssl) { true }

        it 'returns a transport with provided options' do
          default.apis.each_value do |api|
            expect(api.adapter).to be_a_kind_of(Datadog::Transport::HTTP::Adapters::Net)
            expect(api.adapter.hostname).to eq(hostname)
            expect(api.adapter.port).to eq(port)
            expect(api.adapter.timeout).to be(timeout_seconds)
            expect(api.adapter.ssl).to be true
          end
        end
      end

      context 'that specifies a deprecated_for_removal_transport_configuration_proc' do
        let(:deprecated_for_removal_transport_configuration_proc) { proc {} }

        it 'calls the deprecated_for_removal_transport_configuration_proc with the transport builder' do
          expect(deprecated_for_removal_transport_configuration_proc).to \
            receive(:call).with(an_instance_of(Datadog::Transport::HTTP::Builder))

          default
        end
      end
    end

    context 'when given options' do
      subject(:default) { described_class.default(**options) }

      context 'that specify an API version' do
        let(:options) { { api_version: api_version } }

        context 'that is defined' do
          let(:api_version) { Datadog::Transport::HTTP::API::V4 }

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
          default.apis.each_value do |api|
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
        Datadog::Transport::Ext::HTTP::HEADER_CLIENT_COMPUTED_TOP_LEVEL => '1',
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

  describe '.default_adapter' do
    subject(:default_adapter) { described_class.default_adapter }

    it { is_expected.to be(:net_http) }
  end

  describe '.default_hostname' do
    subject(:default_hostname) { described_class.default_hostname(logger: logger) }

    let(:logger) { instance_double(Datadog::Core::Logger, warn: nil) }

    before do
      stub_const(
        'Datadog::Transport::HTTP::DO_NOT_USE_ENVIRONMENT_AGENT_SETTINGS',
        instance_double(Datadog::Core::Configuration::AgentSettingsResolver::AgentSettings, hostname: 'example-hostname')
      )
    end

    it 'returns the hostname from the DO_NOT_USE_ENVIRONMENT_AGENT_SETTINGS object' do
      expect(default_hostname).to eq 'example-hostname'
    end

    it 'logs a deprecation warning' do
      expect(logger).to receive(:warn).with(/Deprecated/)

      default_hostname
    end
  end

  describe '.default_port' do
    subject(:default_port) { described_class.default_port(logger: logger) }

    let(:logger) { instance_double(Datadog::Core::Logger, warn: nil) }

    before do
      stub_const(
        'Datadog::Transport::HTTP::DO_NOT_USE_ENVIRONMENT_AGENT_SETTINGS',
        instance_double(Datadog::Core::Configuration::AgentSettingsResolver::AgentSettings, port: 12345)
      )
    end

    it 'returns the port from the DO_NOT_USE_ENVIRONMENT_AGENT_SETTINGS object' do
      expect(default_port).to eq 12345
    end

    it 'logs a deprecation warning' do
      expect(logger).to receive(:warn).with(/Deprecated/)

      default_port
    end
  end

  describe '.default_url' do
    subject(:default_url) { described_class.default_url(logger: logger) }

    let(:logger) { instance_double(Datadog::Core::Logger, warn: nil) }

    it { is_expected.to be nil }

    it 'logs a deprecation warning' do
      expect(logger).to receive(:warn).with(/Deprecated/)

      default_url
    end
  end
end
