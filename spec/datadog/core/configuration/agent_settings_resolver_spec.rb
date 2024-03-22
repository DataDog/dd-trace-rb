require 'datadog/core/configuration/agent_settings_resolver'
require 'datadog/core/configuration/settings'

RSpec.describe Datadog::Core::Configuration::AgentSettingsResolver do
  around { |example| ClimateControl.modify(default_environment.merge(environment)) { example.run } }

  let(:default_environment) do
    {
      'DD_AGENT_HOST' => nil,
      'DD_TRACE_AGENT_PORT' => nil,
      'DD_TRACE_AGENT_URL' => nil,
      'DD_TRACE_AGENT_TIMEOUT_SECONDS' => nil,
    }
  end
  let(:environment) { {} }
  let(:datadog_settings) { Datadog::Core::Configuration::Settings.new }
  let(:logger) { instance_double(Datadog::Core::Logger) }

  let(:settings) do
    {
      adapter: adapter,
      ssl: false,
      hostname: hostname,
      port: port,
      uds_path: uds_path,
      timeout_seconds: timeout_seconds
    }
  end

  let(:adapter) { :net_http }
  let(:hostname) { '127.0.0.1' }
  let(:port) { 8126 }
  let(:uds_path) { nil }
  let(:timeout_seconds) { 30 }

  before do
    # Environment does not have existing unix socket for the base testing case
    allow(File).to receive(:exist?).and_call_original # To avoid breaking debugging
    allow(File).to receive(:exist?).with('/var/run/datadog/apm.socket').and_return(false)
  end

  subject(:resolver) { described_class.call(datadog_settings, logger: logger) }

  context 'by default' do
    it 'contacts the agent using the http adapter, using hostname 127.0.0.1 and port 8126' do
      expect(resolver).to have_attributes settings
    end

    context 'with default unix socket present' do
      before do
        expect(File).to receive(:exist?).with('/var/run/datadog/apm.socket').and_return(true)
      end

      let(:adapter) { :unix }
      let(:uds_path) { '/var/run/datadog/apm.socket' }
      let(:hostname) { nil }
      let(:port) { nil }
      let(:timeout_seconds) { 1 }

      it 'configures the agent to connect to unix:///var/run/datadog/apm.socket' do
        expect(resolver).to have_attributes(
          **settings,
          adapter: :unix,
          uds_path: '/var/run/datadog/apm.socket',
          hostname: nil,
          port: nil,
        )
      end
    end
  end

  describe 'http adapter hostname' do
    context 'when a custom hostname is specified via the DD_AGENT_HOST environment variable' do
      let(:environment) { { 'DD_AGENT_HOST' => 'custom-hostname' } }

      it 'contacts the agent using the http adapter, using the custom hostname' do
        expect(resolver).to have_attributes(**settings, hostname: 'custom-hostname')
      end
    end

    context 'when a custom hostname is specified via code using "agent.host ="' do
      before do
        datadog_settings.agent.host = 'custom-hostname'
      end

      it 'contacts the agent using the http adapter, using the custom hostname' do
        expect(resolver).to have_attributes(**settings, hostname: 'custom-hostname')
      end
    end

    context 'when a custom hostname is specified via the DD_TRACE_AGENT_URL environment variable' do
      let(:environment) { { 'DD_TRACE_AGENT_URL' => "http://custom-hostname:#{port}" } }

      it 'contacts the agent using the http adapter, using the custom hostname' do
        expect(resolver).to have_attributes(**settings, hostname: 'custom-hostname')
      end
    end

    describe 'priority' do
      let(:with_transport_options) { nil }
      let(:with_agent_host) { nil }
      let(:with_agent_port) { nil }
      let(:with_trace_agent_url) { nil }
      let(:with_environment_agent_host) { nil }
      let(:environment) do
        environment = {}

        (environment['DD_TRACE_AGENT_URL'] = "http://#{with_trace_agent_url}:1234") if with_trace_agent_url
        (environment['DD_AGENT_HOST'] = with_environment_agent_host) if with_environment_agent_host

        environment
      end

      before do
        allow(logger).to receive(:warn)
        (datadog_settings.agent.host = with_agent_host) if with_agent_host
        (datadog_settings.agent.port = with_agent_port) if with_agent_port
      end

      context 'when agent.host, DD_TRACE_AGENT_URL, DD_AGENT_HOST are provided' do
        let(:with_agent_host) { 'custom-hostname-2' }
        let(:with_trace_agent_url) { 'custom-hostname-3' }
        let(:with_environment_agent_host) { 'custom-hostname-4' }

        it 'prioritizes the agent.port' do
          expect(resolver).to have_attributes(hostname: 'custom-hostname-2')
        end

        it 'logs a warning' do
          expect(logger).to receive(:warn).with(/Configuration mismatch/)

          resolver
        end
      end

      context 'when DD_TRACE_AGENT_URL, DD_AGENT_HOST are provided' do
        let(:with_trace_agent_url) { 'custom-hostname-3' }
        let(:with_environment_agent_host) { 'custom-hostname-4' }

        it 'prioritizes the DD_TRACE_AGENT_URL' do
          expect(resolver).to have_attributes(hostname: 'custom-hostname-3')
        end

        it 'logs a warning' do
          expect(logger).to receive(:warn).with(/Configuration mismatch/)

          resolver
        end
      end

      # This somewhat duplicates some of the testing above, but it's still helpful to validate that the test is correct
      # (otherwise it may pass due to bugs, not due to right priority being used)
      context 'when only DD_AGENT_HOST is provided' do
        let(:with_environment_agent_host) { 'custom-hostname-4' }

        it 'uses the DD_AGENT_HOST' do
          expect(resolver).to have_attributes(hostname: 'custom-hostname-4')
        end

        it 'does not log any warning' do
          expect(logger).to_not receive(:warn).with(/Configuration mismatch/)

          resolver
        end
      end

      context 'when there is a mix of http configuration and uds configuration' do
        let(:environment) { super().merge('DD_TRACE_AGENT_URL' => 'unix:///some/path') }

        context 'when there is a hostname specified along with uds configuration' do
          let(:with_agent_host) { 'custom-hostname' }

          it 'prioritizes the http configuration' do
            expect(resolver).to have_attributes(hostname: 'custom-hostname', adapter: :net_http)
          end

          it 'logs a warning including the uds path' do
            expect(logger).to receive(:warn)
              .with(%r{Configuration mismatch.*configuration for unix domain socket \("unix:.*/some/path"\)})

            resolver
          end

          it 'does not include a uds_path in the configuration' do
            expect(resolver).to have_attributes(uds_path: nil)
          end

          context 'when there is no port specified' do
            it 'prioritizes the http configuration and uses the default port' do
              expect(resolver).to have_attributes(port: 8126, hostname: 'custom-hostname', adapter: :net_http)
            end

            it 'logs a warning including the hostname and default port' do
              expect(logger).to receive(:warn)
                .with(/
                  Configuration\ mismatch:\ values\ differ\ between\ configuration.*
                  Using\ "hostname:\ 'custom-hostname',\ port:\ '8126'".*
                /x)

              resolver
            end
          end

          context 'when there is a port specified' do
            let(:with_agent_port) { 1234 }

            it 'prioritizes the http configuration and uses the specified port' do
              expect(resolver).to have_attributes(port: 1234, hostname: 'custom-hostname', adapter: :net_http)
            end

            it 'logs a warning including the hostname and port' do
              expect(logger).to receive(:warn)
                .with(/
                  Configuration\ mismatch:\ values\ differ\ between\ configuration.*
                  Using\ "hostname:\ 'custom-hostname',\ port:\ '1234'".*
                /x)

              resolver
            end
          end
        end

        context 'when there is a port specified along with uds configuration' do
          let(:with_agent_port) { 5678 }

          it 'prioritizes the http configuration' do
            expect(resolver).to have_attributes(port: 5678, adapter: :net_http)
          end

          it 'logs a warning including the uds path' do
            expect(logger).to receive(:warn)
              .with(%r{Configuration mismatch.*configuration for unix domain socket \("unix:.*/some/path"\)})

            resolver
          end

          it 'does not include a uds_path in the configuration' do
            expect(resolver).to have_attributes(uds_path: nil)
          end

          context 'when there is no hostname specified' do
            it 'prioritizes the http configuration and uses the default hostname' do
              expect(resolver).to have_attributes(port: 5678, hostname: '127.0.0.1', adapter: :net_http)
            end

            it 'logs a warning including the default hostname and port' do
              expect(logger).to receive(:warn)
                .with(/
                  Configuration\ mismatch:\ values\ differ\ between\ configuration.*
                  Using\ "hostname:\ '127.0.0.1',\ port:\ '5678'".*
                /x)

              resolver
            end
          end

          context 'when there is a hostname specified' do
            let(:with_agent_host) { 'custom-hostname' }

            it 'prioritizes the http configuration and uses the specified hostname' do
              expect(resolver).to have_attributes(port: 5678, hostname: 'custom-hostname', adapter: :net_http)
            end

            it 'logs a warning including the hostname and port' do
              expect(logger).to receive(:warn)
                .with(/
                  Configuration\ mismatch:\ values\ differ\ between\ configuration.*
                  Using\ "hostname:\ 'custom-hostname',\ port:\ '5678'".*
                /x)

              resolver
            end
          end
        end
      end
    end
  end

  describe 'http adapter port' do
    shared_examples_for "parsing of port when it's not an integer" do
      context 'when the port is specified as a string instead of a number' do
        let(:port_value_to_parse) { '1234' }

        it 'contacts the agent using the http adapter, using the custom port' do
          expect(resolver).to have_attributes(**settings, port: 1234)
        end
      end

      context 'when the port is an invalid string value' do
        let(:port_value_to_parse) { 'kaboom' }

        before do
          allow(logger).to receive(:warn)
        end

        it 'logs a warning' do
          expect(logger).to receive(:warn).with(/Invalid value/)

          resolver
        end

        it 'falls back to the defaults' do
          expect(resolver).to have_attributes settings
        end
      end

      context 'when the port is an invalid object' do
        let(:port_value_to_parse) { Object.new }

        before do
          allow(logger).to receive(:warn)
        end

        it 'logs a warning' do
          expect(logger).to receive(:warn).with(/Invalid value/)

          resolver
        end

        it 'falls back to the defaults' do
          expect(resolver).to have_attributes settings
        end
      end
    end

    context 'when a custom port is specified via the DD_TRACE_AGENT_PORT environment variable' do
      let(:environment) { { 'DD_TRACE_AGENT_PORT' => '1234' } }

      it 'contacts the agent using the http adapter, using the custom port' do
        expect(resolver).to have_attributes(**settings, port: 1234)
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
          expect(resolver).to have_attributes settings
        end
      end
    end

    context 'when a custom port is specified via code using "agent.port = "' do
      before do
        datadog_settings.agent.port = 1234
      end

      it 'contacts the agent using the http adapter, using the custom port' do
        expect(resolver).to have_attributes(**settings, port: 1234)
      end

      it_behaves_like "parsing of port when it's not an integer" do
        before do
          datadog_settings.agent.port = port_value_to_parse
        end
      end
    end

    context 'when a custom port is specified via the DD_TRACE_AGENT_URL environment variable' do
      let(:environment) { { 'DD_TRACE_AGENT_URL' => "http://#{hostname}:1234" } }

      it 'contacts the agent using the http adapter, using the custom port' do
        expect(resolver).to have_attributes(**settings, port: 1234)
      end
    end

    describe 'priority' do
      let(:with_agent_port) { nil }
      let(:with_trace_agent_url) { nil }
      let(:with_trace_agent_port) { nil }
      let(:environment) do
        environment = {}

        (environment['DD_TRACE_AGENT_URL'] = "http://custom-hostname:#{with_trace_agent_url}") if with_trace_agent_url
        (environment['DD_TRACE_AGENT_PORT'] = with_trace_agent_port.to_s) if with_trace_agent_port

        environment
      end

      before do
        allow(logger).to receive(:warn)
        (datadog_settings.agent.port = with_agent_port) if with_agent_port
      end

      context 'when all of agent.port, DD_TRACE_AGENT_URL, DD_TRACE_AGENT_PORT are provided' do
        let(:with_agent_port) { 2 }
        let(:with_trace_agent_url) { 3 }
        let(:with_trace_agent_port) { 4 }

        it 'prioritizes the agent.port' do
          expect(resolver).to have_attributes(port: 2)
        end

        it 'logs a warning' do
          expect(logger).to receive(:warn).with(/Configuration mismatch/)

          resolver
        end
      end

      context 'when DD_TRACE_AGENT_URL, DD_TRACE_AGENT_PORT are provided' do
        let(:with_trace_agent_url) { 3 }
        let(:with_trace_agent_port) { 4 }

        it 'prioritizes the DD_TRACE_AGENT_URL' do
          expect(resolver).to have_attributes(port: 3)
        end

        it 'logs a warning' do
          expect(logger).to receive(:warn).with(/Configuration mismatch/)

          resolver
        end
      end

      # This somewhat duplicates some of the testing above, but it's still helpful to validate that the test is correct
      # (otherwise it may pass due to bugs, not due to right priority being used)
      context 'when only DD_TRACE_AGENT_PORT is provided' do
        let(:with_trace_agent_port) { 4 }

        it 'uses the DD_TRACE_AGENT_PORT' do
          expect(resolver).to have_attributes(port: 4)
        end

        it 'does not log any warning' do
          expect(logger).to_not receive(:warn).with(/Configuration mismatch/)

          resolver
        end
      end
    end
  end

  describe 'timeout' do
    shared_examples_for "parsing of timeout when it's not an integer" do
      context 'when the timeout is specified as a string instead of a number' do
        let(:timeout_value_to_parse) { '777' }

        it 'contacts the agent using the http adapter, using the custom timeout' do
          expect(resolver).to have_attributes(**settings, timeout_seconds: 777)
        end
      end

      context 'when the timeout is an invalid string value' do
        let(:timeout_value_to_parse) { 'timeout' }

        before do
          allow(logger).to receive(:warn)
        end

        it 'logs a warning' do
          expect(logger).to receive(:warn).with(/Invalid value/)

          resolver
        end

        it 'falls back to the defaults' do
          expect(resolver).to have_attributes settings
        end
      end

      context 'when the timeout is an invalid object' do
        let(:timeout_value_to_parse) { Object.new }

        before do
          allow(logger).to receive(:warn)
        end

        it 'logs a warning' do
          expect(logger).to receive(:warn).with(/Invalid value/)

          resolver
        end

        it 'falls back to the defaults' do
          expect(resolver).to have_attributes settings
        end
      end
    end

    context 'when a custom timeout is specified via the DD_TRACE_AGENT_TIMEOUT_SECONDS environment variable' do
      let(:environment) { { 'DD_TRACE_AGENT_TIMEOUT_SECONDS' => '798' } }

      it 'contacts the agent using the http adapter, using the custom timeout' do
        expect(resolver).to have_attributes(**settings, timeout_seconds: 798)
      end

      context 'when the custom timeout is invalid' do
        let(:environment) { { 'DD_TRACE_AGENT_TIMEOUT_SECONDS' => 'this-is-an-invalid-timeout' } }

        before do
          allow(logger).to receive(:warn)
        end

        it 'logs a warning' do
          expect(logger).to receive(:warn).with(/Invalid value/)

          resolver
        end

        it 'falls back to the defaults' do
          expect(resolver).to have_attributes settings
        end
      end
    end

    context 'when a custom timeout is specified via code using "agent.timeout_seconds = "' do
      before do
        datadog_settings.agent.timeout_seconds = 111
      end

      it 'contacts the agent using the http adapter, using the custom timeout' do
        expect(resolver).to have_attributes(**settings, timeout_seconds: 111)
      end

      it_behaves_like "parsing of timeout when it's not an integer" do
        before do
          datadog_settings.agent.timeout_seconds = timeout_value_to_parse
        end
      end
    end

    describe 'priority' do
      let(:with_agent_timeout) { nil }
      let(:with_env_agent_timeout) { nil }
      let(:environment) do
        environment = {}

        (environment['DD_TRACE_AGENT_TIMEOUT_SECONDS'] = with_env_agent_timeout.to_s) if with_env_agent_timeout

        environment
      end

      before do
        allow(logger).to receive(:warn)
        (datadog_settings.agent.timeout_seconds = with_agent_timeout) if with_agent_timeout
      end

      context 'when all of agent.timeout_seconds, DD_TRACE_AGENT_TIMEOUT_SECONDS are provided' do
        let(:with_agent_timeout) { 17 }
        let(:with_env_agent_timeout) { 39 }

        it 'prioritizes the agent.timeout_seconds' do
          expect(resolver).to have_attributes(timeout_seconds: 17)
        end

        it 'logs a warning' do
          expect(logger).to receive(:warn).with(/Configuration mismatch/)

          resolver
        end
      end

      context 'when only DD_TRACE_AGENT_TIMEOUT_SECONDS is provided' do
        let(:with_env_agent_timeout) { 9 }

        it 'uses the DD_TRACE_AGENT_TIMEOUT_SECONDS' do
          expect(resolver).to have_attributes(timeout_seconds: 9)
        end

        it 'does not log any warning' do
          expect(logger).to_not receive(:warn).with(/Configuration mismatch/)

          resolver
        end
      end
    end
  end

  describe 'ssl' do
    context 'When agent.use_ssl is set' do
      before do
        datadog_settings.agent.use_ssl = agent_use_ssl
      end

      context 'when agent.use_ssl is true' do
        let(:agent_use_ssl) { true }

        it 'contacts the agent using ssl' do
          expect(resolver).to have_attributes(ssl: true)
        end
      end

      context 'when agent.use_ssl is false' do
        let(:agent_use_ssl) { false }

        it 'contacts the agent without ssl' do
          expect(resolver).to have_attributes(ssl: false)
        end
      end
    end

    context 'when DD_TRACE_AGENT_URL is set' do
      let(:environment) { { 'DD_TRACE_AGENT_URL' => "#{trace_agent_url_protocol}://custom-hostname:1234" } }

      context 'when set to https' do
        let(:trace_agent_url_protocol) { 'https' }

        it 'contacts the agent using ssl' do
          expect(resolver).to have_attributes(ssl: true)
        end
      end

      context 'when http is specified' do
        let(:trace_agent_url_protocol) { 'http' }

        it 'contacts the agent without ssl' do
          expect(resolver).to have_attributes(ssl: false)
        end
      end
    end

    describe 'priority' do
      let(:environment) do
        environment = {}
        (environment['DD_TRACE_AGENT_URL'] = "#{trace_agent_url_protocol}://agent_hostname:1234") if with_trace_agent_url

        environment
      end

      before do
        allow(logger).to receive(:warn)
        (datadog_settings.agent.use_ssl = with_agent_use_ssl) if with_agent_use_ssl
      end

      context 'when agent.use_ssl, DD_TRACE_AGENT_URL are provided' do
        let(:with_agent_use_ssl) { true }
        let(:with_trace_agent_url) { true }
        let(:trace_agent_url_protocol) { 'http' }
        let(:with_environment_agent_use_ssl_value) { false }

        it 'prioritizes the agent.use_ssl' do
          expect(resolver).to have_attributes(ssl: true)
        end

        it 'logs a warning' do
          expect(logger).to receive(:warn).with(/Configuration mismatch/)

          resolver
        end
      end

      context 'Only DD_TRACE_AGENT_URL is provided' do
        let(:with_agent_use_ssl) { false }
        let(:with_trace_agent_url) { true }
        let(:trace_agent_url_protocol) { 'https' }

        it 'prioritizes the DD_TRACE_URL' do
          expect(resolver).to have_attributes(ssl: true)
        end

        it 'does not log any warning' do
          expect(logger).to_not receive(:warn).with(/Configuration mismatch/)

          resolver
        end
      end
    end
  end

  context 'when a custom url is specified via environment variable' do
    let(:environment) { { 'DD_TRACE_AGENT_URL' => 'http://custom-hostname:1234' } }

    it 'contacts the agent using the http adapter, using the custom hostname and port' do
      expect(resolver).to have_attributes(
        **settings,
        ssl: false,
        hostname: 'custom-hostname',
        port: 1234
      )
    end

    context 'when the uri scheme is https' do
      let(:environment) { { 'DD_TRACE_AGENT_URL' => 'https://custom-hostname:1234' } }

      it 'contacts the agent using the http adapter, using ssl: true' do
        expect(resolver).to have_attributes(ssl: true)
      end
    end

    context 'when the uri scheme is unix' do
      let(:environment) { { 'DD_TRACE_AGENT_URL' => 'unix:///path/to/apm.socket' } }
      let(:timeout_seconds) { 1 }

      it 'contacts the agent via a unix domain socket' do
        expect(resolver).to have_attributes(
          **settings,
          adapter: :unix,
          uds_path: '/path/to/apm.socket',
          hostname: nil,
          port: nil,
        )
      end
    end

    context 'when the uri scheme is not http OR https' do
      let(:environment) { { 'DD_TRACE_AGENT_URL' => 'steam://custom-hostname:1234' } }

      before do
        allow(logger).to receive(:warn)
      end

      it 'falls back to the defaults' do
        expect(resolver).to have_attributes settings
      end

      it 'logs a warning' do
        expect(logger).to receive(:warn).with(/Invalid URI scheme/)

        resolver
      end
    end
  end

  describe 'uds_path' do
    let(:hostname) { nil }
    let(:port) { nil }
    let(:timeout_seconds) { 1 }
    let(:adapter) { :unix }

    context 'when a custom path is specified via code using "agent.uds_path ="' do
      before do
        datadog_settings.agent.uds_path = '/var/code/custom.socket'
      end

      it 'contacts the agent using the unix adapter, using the custom path' do
        expect(resolver).to have_attributes(**settings, uds_path: '/var/code/custom.socket')
      end
    end

    context 'when a custom path is specified via the DD_TRACE_AGENT_URL environment variable' do
      let(:environment) { { 'DD_TRACE_AGENT_URL' => 'unix:///var/uri.socket' } }

      it 'contacts the agent using the unix adapter, using the custom path' do
        expect(resolver).to have_attributes(**settings, uds_path: '/var/uri.socket')
      end
    end

    describe 'priority' do
      let(:with_agent_uds_path) { nil }
      let(:with_trace_agent_url) { nil }
      let(:environment) do
        environment = {}

        (environment['DD_TRACE_AGENT_URL'] = "unix://#{with_trace_agent_url}") if with_trace_agent_url

        environment
      end

      before do
        allow(logger).to receive(:warn)
        (datadog_settings.agent.uds_path = with_agent_uds_path) if with_agent_uds_path
      end

      context 'when agent.uds_path, DD_TRACE_AGENT_URL are provided' do
        let(:with_agent_uds_path) { '/var/uds/path.socket' }
        let(:with_trace_agent_url) { 'var/trace/agent.socket' }

        it 'prioritizes the agent.uds_path' do
          expect(resolver).to have_attributes(uds_path: '/var/uds/path.socket')
        end

        it 'logs a warning' do
          expect(logger).to receive(:warn).with(/Configuration mismatch/)

          resolver
        end
      end

      # This somewhat duplicates some of the testing above, but it's still helpful to validate that the test is correct
      # (otherwise it may pass due to bugs, not due to right priority being used)
      context 'when only DD_TRACE_AGENT_URL is provided' do
        let(:with_trace_agent_url) { '/var/trace/agent.socket' }

        it 'uses the DD_TRACE_AGENT_URL_PATH' do
          expect(resolver).to have_attributes(uds_path: '/var/trace/agent.socket')
        end

        it 'does not log any warning' do
          expect(logger).to_not receive(:warn).with(/Configuration mismatch/)

          resolver
        end
      end
    end
  end

  describe '#log_warning' do
    let(:message) { 'this is a test warning' }

    subject(:log_warning) do
      described_class.new(datadog_settings, logger: logger).send(:log_warning, message)
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
