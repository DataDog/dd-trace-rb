require 'ddtrace/configuration/agent_settings_resolver'
require 'ddtrace/configuration/settings'

RSpec.describe Datadog::Configuration::AgentSettingsResolver do
  around { |example| ClimateControl.modify(default_environment.merge(environment)) { example.run } }

  let(:default_environment) do
    {
      'DD_AGENT_HOST' => nil,
      'DD_TRACE_AGENT_PORT' => nil,
      'DD_TRACE_AGENT_URL' => nil
    }
  end
  let(:environment) { {} }
  let(:ddtrace_settings) { Datadog::Configuration::Settings.new }
  let(:logger) { instance_double(Datadog::Logger) }

  let(:default_settings) do
    {
      ssl: false,
      hostname: '127.0.0.1',
      port: 8126,
      timeout_seconds: 1,
      deprecated_for_removal_transport_configuration_proc: nil,
      deprecated_for_removal_transport_configuration_options: nil
    }
  end

  subject(:resolver) { described_class.call(ddtrace_settings, logger: logger) }

  context 'by default' do
    it 'contacts the agent using the http adapter, using hostname 127.0.0.1 and port 8126' do
      expect(resolver).to have_attributes default_settings
    end
  end

  describe 'http adapter hostname' do
    context 'when a custom hostname is specified via environment variable' do
      let(:environment) { { 'DD_AGENT_HOST' => 'custom-hostname' } }

      it 'contacts the agent using the http adapter, using the custom hostname' do
        expect(resolver).to have_attributes(**default_settings, hostname: 'custom-hostname')
      end
    end

    context 'when a custom hostname is specified via code using "tracer.hostname ="' do
      before do
        ddtrace_settings.tracer.hostname = 'custom-hostname'
      end

      it 'contacts the agent using the http adapter, using the custom hostname' do
        expect(resolver).to have_attributes(**default_settings, hostname: 'custom-hostname')
      end

      context 'and a different hostname is also specified via the DD_AGENT_HOST environment variable' do
        let(:environment) { { 'DD_AGENT_HOST' => 'this-is-a-different-hostname' } }

        before do
          allow(logger).to receive(:warn)
        end

        it 'prioritizes the hostname specified via code' do
          expect(resolver).to have_attributes(**default_settings, hostname: 'custom-hostname')
        end

        it 'logs a warning' do
          expect(logger).to receive(:warn).with(/Configuration mismatch/)

          resolver
        end
      end

      context 'and a different hostname is also specified via the DD_TRACE_AGENT_URL environment variable' do
        let(:environment) { { 'DD_TRACE_AGENT_URL' => 'http://this-is-a-different-hostname:8126' } }

        before do
          allow(logger).to receive(:warn)
        end

        it 'prioritizes the hostname specified via code' do
          expect(resolver).to have_attributes(**default_settings, hostname: 'custom-hostname')
        end

        it 'logs a warning' do
          expect(logger).to receive(:warn).with(/Configuration mismatch/)

          resolver
        end
      end
    end

    context 'when a custom hostname is specified via code using "tracer(hostname: ...)"' do
      before do
        ddtrace_settings.tracer(hostname: 'custom-hostname')
      end

      it 'contacts the agent using the http adapter, using the custom hostname' do
        expect(resolver).to have_attributes(**default_settings, hostname: 'custom-hostname')
      end
    end
  end

  describe 'http adapter port' do
    context 'when a custom port is specified via environment variable' do
      let(:environment) { { 'DD_TRACE_AGENT_PORT' => '1234' } }

      it 'contacts the agent using the http adapter, using the custom port' do
        expect(resolver).to have_attributes(**default_settings, port: 1234)
      end

      context 'when the custom port is invalid' do
        let(:environment) { { 'DD_TRACE_AGENT_PORT' => 'this-is-an-invalid-port' } }

        before do
          allow(logger).to receive(:warn)
        end

        it 'logs a warning' do
          expect(logger).to receive(:warn).with(/Invalid value/)

          resolver
        end

        it 'falls back to the defaults' do
          expect(resolver).to have_attributes default_settings
        end
      end
    end

    context 'when a custom port is specified via code using "tracer.port = "' do
      before do
        ddtrace_settings.tracer.port = 1234
      end

      it 'contacts the agent using the http adapter, using the custom port' do
        expect(resolver).to have_attributes(**default_settings, port: 1234)
      end

      context 'and a different port is also specified via the DD_TRACE_AGENT_PORT environment variable' do
        let(:environment) { { 'DD_TRACE_AGENT_PORT' => '5678' } }

        before do
          allow(logger).to receive(:warn)
        end

        it 'prioritizes the port specified via code' do
          expect(resolver).to have_attributes(**default_settings, port: 1234)
        end

        it 'logs a warning' do
          expect(logger).to receive(:warn).with(/Configuration mismatch/)

          resolver
        end
      end

      context 'and a different port is also specified via the DD_TRACE_AGENT_URL environment variable' do
        let(:environment) { { 'DD_TRACE_AGENT_URL' => 'http://127.0.0.1:5678' } }

        before do
          allow(logger).to receive(:warn)
        end

        it 'prioritizes the port specified via code' do
          expect(resolver).to have_attributes(**default_settings, port: 1234)
        end

        it 'logs a warning' do
          expect(logger).to receive(:warn).with(/Configuration mismatch/)

          resolver
        end
      end
    end

    context 'when a custom port is specified via code using "tracer(port: ...)"' do
      before do
        ddtrace_settings.tracer(port: 1234)
      end

      it 'contacts the agent using the http adapter, using the custom port' do
        expect(resolver).to have_attributes(**default_settings, port: 1234)
      end
    end
  end

  context 'when a custom url is specified via environment variable' do
    let(:environment) { { 'DD_TRACE_AGENT_URL' => 'http://custom-hostname:1234' } }

    it 'contacts the agent using the http adapter, using the custom hostname and port' do
      expect(resolver).to have_attributes(
        **default_settings,
        ssl: false,
        hostname: 'custom-hostname',
        port: 1234
      )
    end

    context 'and a different hostname is also specified via the DD_AGENT_HOST environment variable' do
      let(:environment) do
        {
          'DD_TRACE_AGENT_URL' => 'http://custom-hostname:1234',
          'DD_AGENT_HOST' => 'this-is-a-different-hostname'
        }
      end

      before do
        allow(logger).to receive(:warn)
      end

      it 'prioritizes the hostname specified via DD_TRACE_AGENT_URL' do
        expect(resolver).to have_attributes(hostname: 'custom-hostname')
      end

      it 'logs a warning' do
        expect(logger).to receive(:warn).with(/Configuration mismatch/)

        resolver
      end
    end

    context 'and a different port is also specified via the DD_TRACE_AGENT_PORT environment variable' do
      let(:environment) do
        {
          'DD_TRACE_AGENT_URL' => 'http://custom-hostname:1234',
          'DD_TRACE_AGENT_PORT' => '5678'
        }
      end

      before do
        allow(logger).to receive(:warn)
      end

      it 'prioritizes the port specified via DD_TRACE_AGENT_URL' do
        expect(resolver).to have_attributes(port: 1234)
      end

      it 'logs a warning' do
        expect(logger).to receive(:warn).with(/Configuration mismatch/)

        resolver
      end
    end

    context 'when the uri scheme is https' do
      let(:environment) { { 'DD_TRACE_AGENT_URL' => 'https://custom-hostname:1234' } }

      it 'contacts the agent using the http adapter, using ssl: true' do
        expect(resolver).to have_attributes(ssl: true)
      end
    end

    context 'when the uri scheme is not http OR https' do
      let(:environment) { { 'DD_TRACE_AGENT_URL' => 'steam://custom-hostname:1234' } }

      before do
        allow(logger).to receive(:warn)
      end

      it 'falls back to the defaults' do
        expect(resolver).to have_attributes default_settings
      end

      it 'logs a warning' do
        expect(logger).to receive(:warn).with(/Invalid URI scheme/)

        resolver
      end
    end
  end

  context 'when a proc is configured in tracer.transport_options' do
    let(:deprecated_for_removal_transport_configuration_proc) { proc {} }

    before do
      ddtrace_settings.tracer.transport_options = deprecated_for_removal_transport_configuration_proc
    end

    it 'includes the given proc in the resolved settings as the deprecated_for_removal_transport_configuration_proc' do
      expect(resolver).to have_attributes(
        **default_settings,
        deprecated_for_removal_transport_configuration_proc: deprecated_for_removal_transport_configuration_proc
      )
    end
  end

  context 'when a non-empty hash is configured in tracer.transport_options' do
    let(:deprecated_for_removal_transport_configuration_options) { { batman: :cool } }

    before do
      ddtrace_settings.tracer.transport_options = deprecated_for_removal_transport_configuration_options
      allow(logger).to receive(:warn)
    end

    it 'includes the given hash in the resolved settings as the deprecated_for_removal_transport_configuration_options' do
      expect(resolver).to have_attributes(
        **default_settings,
        deprecated_for_removal_transport_configuration_options: deprecated_for_removal_transport_configuration_options
      )
    end

    it 'logs a deprecation warning' do
      expect(logger).to receive(:warn).with(/deprecated for removal/)

      resolver
    end
  end

  describe '#log_warning' do
    let(:message) { 'this is a test warning' }

    subject(:log_warning) do
      described_class.new(ddtrace_settings, logger: logger).send(:log_warning, message)
    end

    it 'logs a warning used the configured logger' do
      expect(logger).to receive(:warn).with('this is a test warning')

      log_warning
    end

    context 'when logger is nil' do
      let(:logger) { nil }

      it 'does not log anything' do
        log_warning
      end
    end
  end
end
