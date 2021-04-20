require 'ddtrace/configuration/agent_settings_resolver'
require 'ddtrace/configuration/settings'

RSpec.describe Datadog::Configuration::AgentSettingsResolver do
  around { |example| ClimateControl.modify(**default_environment, **environment) { example.run } }

  let(:default_environment) {
    {
      'DD_AGENT_HOST' => nil,
      'DD_TRACE_AGENT_PORT' => nil,
      'DD_TRACE_AGENT_URL' => nil,
    }
  }
  let(:environment) { Hash.new }
  let(:ddtrace_settings) { Datadog::Configuration::Settings.new }
  let(:logger) { instance_double(Datadog::Logger) }

  let(:default_settings) {
    {
      adapter: :http,
      ssl: false,
      hostname: '127.0.0.1',
      port: 8126
    }
  }

  subject { described_class.new(ddtrace_settings, logger: logger) }

  context 'by default' do
    it 'contacts the agent using the http adapter, using hostname 127.0.0.1 and port 8126' do
      expect(subject.call).to eq default_settings
    end
  end

  describe 'http adapter hostname' do
    context 'when a custom hostname is specified via environment variable' do
      let(:environment) { {'DD_AGENT_HOST' => 'custom-hostname'} }

      it 'contacts the agent using the http adapter, using the custom hostname' do
        expect(subject.call).to eq(**default_settings, hostname: 'custom-hostname')
      end
    end

    context 'when a custom hostname is specified via code using "tracer.hostname ="' do
      before do
        ddtrace_settings.tracer.hostname = 'custom-hostname'
      end

      it 'contacts the agent using the http adapter, using the custom hostname' do
        expect(subject.call).to eq(**default_settings, hostname: 'custom-hostname')
      end

      context 'and a different hostname is also specified via the DD_AGENT_HOST environment variable' do
        let(:environment) { {'DD_AGENT_HOST' => 'this-is-a-different-hostname'} }

        before do
          allow(logger).to receive(:warn)
        end

        it 'prioritizes the hostname specified via code' do
          expect(subject.call).to eq(**default_settings, hostname: 'custom-hostname')
        end

        it 'logs a warning' do
          expect(logger).to receive(:warn).with(/Configuration mismatch/)

          subject.call
        end
      end

      context 'and a different hostname is also specified via the DD_TRACE_AGENT_URL environment variable' do
        let(:environment) { {'DD_TRACE_AGENT_URL' => 'http://this-is-a-different-hostname:8126'} }

        before do
          allow(logger).to receive(:warn)
        end

        it 'prioritizes the hostname specified via code' do
          expect(subject.call).to eq(**default_settings, hostname: 'custom-hostname')
        end

        it 'logs a warning' do
          expect(logger).to receive(:warn).with(/Configuration mismatch/)

          subject.call
        end
      end
    end
  end

  context 'when a custom port is specified via environment variable' do
    let(:environment) { {'DD_TRACE_AGENT_PORT' => '1234'} }

    it 'contacts the agent using the http adapter, using the custom port' do
      expect(subject.call).to eq(**default_settings, port: 1234)
    end

    context 'when the custom port is invalid' do
      let(:environment) { {'DD_TRACE_AGENT_PORT' => 'this-is-an-invalid-port'} }

      before do
        allow(logger).to receive(:warn)
      end

      it 'logs a warning' do
        expect(logger).to receive(:warn).with(/Invalid value/)

        subject.call
      end

      it 'falls back to the defaults' do
        expect(subject.call).to eq default_settings
      end
    end
  end

  context 'when a custom url is specified via environment variable' do
    let(:environment) { {'DD_TRACE_AGENT_URL' => 'http://custom-hostname:1234'} }

    it 'contacts the agent using the http adapter, using the custom hostname and port' do
      expect(subject.call).to eq(
        adapter: :http,
        ssl: false,
        hostname: 'custom-hostname',
        port: 1234
      )
    end

    context 'and a different hostname is also specified via the DD_AGENT_HOST environment variable' do
      let(:environment) {
        {
          'DD_TRACE_AGENT_URL' => 'http://custom-hostname:1234',
          'DD_AGENT_HOST' => 'this-is-a-different-hostname',
        }
      }

      before do
        allow(logger).to receive(:warn)
      end

      it 'it prioritizes the hostname specified via DD_TRACE_AGENT_URL' do
        expect(subject.call).to include(hostname: 'custom-hostname')
      end

      it 'logs a warning' do
        expect(logger).to receive(:warn).with(/Configuration mismatch/)

        subject.call
      end
    end

    context 'and a different port is also specified via the DD_TRACE_AGENT_PORT environment variable' do
      let(:environment) {
        {
          'DD_TRACE_AGENT_URL' => 'http://custom-hostname:1234',
          'DD_TRACE_AGENT_PORT' => '5678',
        }
      }

      before do
        allow(logger).to receive(:warn)
      end

      it 'prioritizes the port specified via DD_TRACE_AGENT_URL' do
        expect(subject.call).to include(port: 1234)
      end

      it 'logs a warning' do
        expect(logger).to receive(:warn).with(/Configuration mismatch/)

        subject.call
      end
    end

    context 'when the uri scheme is https' do
      let(:environment) { {'DD_TRACE_AGENT_URL' => 'https://custom-hostname:1234'} }

      it 'contacts the agent using the http adapter, using ssl: true' do
        expect(subject.call).to include(ssl: true)
      end
    end

    context 'when the uri scheme is not http OR https' do
      let(:environment) { {'DD_TRACE_AGENT_URL' => 'steam://custom-hostname:1234'} }

      it 'falls back to the defaults' do
        expect(subject.call).to eq default_settings
      end

      before do
        allow(logger).to receive(:warn)
      end

      it 'logs a warning' do
        expect(logger).to receive(:warn).with(/Invalid URI scheme/)

        subject.call
      end
    end
  end
end
