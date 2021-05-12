require 'spec_helper'

require 'ddtrace/diagnostics/environment_logger'

require 'ddtrace'

RSpec.describe Datadog::Diagnostics::EnvironmentLogger do
  subject(:env_logger) { described_class }

  before { allow(DateTime).to receive(:now).and_return(DateTime.new(2020)) }

  # Reading DD_AGENT_HOST allows this to work in CI
  let(:agent_hostname) { ENV['DD_AGENT_HOST'] || '127.0.0.1' }

  before do
    # Resets "only-once" execution pattern of `log!`
    env_logger.instance_variable_set(:@executed, nil)

    Datadog.configure.reset!
  end

  describe '#log!' do
    subject(:log!) { env_logger.log!([response]) }

    let(:logger) do
      log!
      tracer_logger
    end

    let(:response) { instance_double(Datadog::Transport::Response, ok?: true) }
    let(:tracer_logger) { instance_double(Datadog::Logger) }

    before do
      allow(Datadog).to receive(:logger).and_return(tracer_logger)
      allow(tracer_logger).to receive(:info)
    end

    it 'with a default tracer settings' do
      expect(logger).to have_received(:info).with start_with('DATADOG TRACER CONFIGURATION') do |msg|
        json = JSON.parse(msg.partition('-')[2].strip)
        expect(json).to match(
          'agent_url' => "http://#{agent_hostname}:8126?timeout=1",
          'analytics_enabled' => false,
          'date' => '2020-01-01T00:00:00+00:00',
          'debug' => false,
          'enabled' => true,
          'health_metrics_enabled' => false,
          'lang' => 'ruby',
          'lang_version' => match(/[23]\./),
          'os_name' => include('x86_64'),
          'partial_flushing_enabled' => false,
          'priority_sampling_enabled' => false,
          'runtime_metrics_enabled' => false,
          'version' => Datadog::VERSION::STRING,
          'vm' => be_a(String)
        )
      end
    end

    context 'with multiple invocations' do
      it 'executes only once' do
        env_logger.log!([response])
        env_logger.log!([response])

        expect(logger).to have_received(:info).once
      end
    end

    context 'with agent error' do
      before { allow(tracer_logger).to receive(:warn) }

      let(:response) { Datadog::Transport::InternalErrorResponse.new(ZeroDivisionError.new('msg')) }

      it do
        expect(logger).to have_received(:warn).with start_with('DATADOG TRACER DIAGNOSTIC') do |msg|
          error_line = msg.partition('-')[2].strip
          error = error_line.partition(':')[2].strip

          expect(error_line).to start_with('Agent Error')
          expect(error).to include('ZeroDivisionError')
          expect(error).to include('msg')
        end
      end
    end

    context 'under a REPL' do
      around do |example|
        begin
          original = $PROGRAM_NAME
          $0 = 'irb'
          example.run
        ensure
          $0 = original
        end
      end

      context 'with default settings' do
        it { expect(logger).to_not have_received(:info) }
      end

      context 'with explicit setting' do
        before do
          Datadog.configure { |c| c.diagnostics.startup_logs.enabled = true }
        end

        it { expect(logger).to have_received(:info) }
      end
    end

    context 'with error collecting information' do
      before do
        allow(tracer_logger).to receive(:warn)
        expect_any_instance_of(Datadog::Diagnostics::EnvironmentCollector).to receive(:collect!).and_raise
      end

      it 'rescues error and logs exception' do
        expect(logger).to have_received(:warn).with start_with('Failed to collect environment information')
      end
    end
  end

  describe Datadog::Diagnostics::EnvironmentCollector do
    describe '#collect!' do
      subject(:collect!) { collector.collect!([response]) }

      let(:collector) { described_class.new }
      let(:response) { instance_double(Datadog::Transport::Response, ok?: true) }

      it 'with a default tracer' do
        is_expected.to match(
          agent_error: nil,
          agent_url: "http://#{agent_hostname}:8126?timeout=1",
          analytics_enabled: false,
          date: '2020-01-01T00:00:00+00:00',
          dd_version: nil,
          debug: false,
          enabled: true,
          env: nil,
          health_metrics_enabled: false,
          integrations_loaded: nil,
          lang: 'ruby',
          lang_version: match(/[23]\./),
          os_name: include('x86_64'),
          partial_flushing_enabled: false,
          priority_sampling_enabled: false,
          runtime_metrics_enabled: false,
          sample_rate: nil,
          sampling_rules: nil,
          service: nil,
          tags: nil,
          version: Datadog::VERSION::STRING,
          vm: be_a(String)
        )
      end

      context 'with tracer disabled' do
        before { Datadog.configure { |c| c.tracer.enabled = false } }

        after { Datadog.configure { |c| c.tracer.enabled = true } }

        it { is_expected.to include enabled: false }
      end

      context 'with env configured' do
        before { Datadog.configure { |c| c.env = 'env' } }

        it { is_expected.to include env: 'env' }
      end

      context 'with tags configured' do
        before { Datadog.configure { |c| c.tags = { 'k1' => 'v1', 'k2' => 'v2' } } }

        it { is_expected.to include tags: 'k1:v1,k2:v2' }
      end

      context 'with service configured' do
        before { Datadog.configure { |c| c.service = 'svc' } }

        it { is_expected.to include service: 'svc' }
      end

      context 'with version configured' do
        before { Datadog.configure { |c| c.version = '1.2' } }

        it { is_expected.to include dd_version: '1.2' }
      end

      context 'with debug enabled' do
        before { Datadog.configure { |c| c.diagnostics.debug = true } }

        it { is_expected.to include debug: true }
      end

      context 'with analytics enabled' do
        before { Datadog.configure { |c| c.analytics_enabled = true } }

        it { is_expected.to include analytics_enabled: true }
      end

      context 'with runtime metrics enabled' do
        before { Datadog.configure { |c| c.runtime_metrics.enabled = true } }

        after { Datadog.configure.runtime_metrics.reset! }

        it { is_expected.to include runtime_metrics_enabled: true }
      end

      context 'with partial flushing enabled' do
        before { Datadog.configure { |c| c.tracer.partial_flush.enabled = true } }

        it { is_expected.to include partial_flushing_enabled: true }
      end

      context 'with priority sampling enabled' do
        before { Datadog.configure { |c| c.tracer.priority_sampling = true } }

        it { is_expected.to include priority_sampling_enabled: true }
      end

      context 'with health metrics enabled' do
        before { Datadog.configure { |c| c.diagnostics.health_metrics.enabled = true } }

        it { is_expected.to include health_metrics_enabled: true }
      end

      context 'with agent connectivity issues' do
        let(:response) { Datadog::Transport::InternalErrorResponse.new(ZeroDivisionError.new('msg')) }

        it { is_expected.to include agent_error: include('ZeroDivisionError') }
        it { is_expected.to include agent_error: include('msg') }
      end

      context 'with unix socket transport' do
        before do
          Datadog.configure do |c|
            c.tracer.transport_options = ->(t) { t.adapter :unix, '/tmp/trace.sock' }
          end
        end

        after { Datadog.configure { |c| c.tracer.transport_options = {} } }

        it { is_expected.to include agent_url: include('unix') }
        it { is_expected.to include agent_url: include('/tmp/trace.sock') }
      end

      context 'with integrations loaded' do
        before { Datadog.configure { |c| c.use :http, options } }

        let(:options) { {} }

        it { is_expected.to include integrations_loaded: start_with('http') }

        it do
          # Because net/http is default gem, we use the Ruby version as the library version.
          is_expected.to include integrations_loaded: end_with("@#{RUBY_VERSION}")
        end

        context 'with integration-specific settings' do
          let(:options) { { service_name: 'my-http' } }

          it { is_expected.to include integration_http_analytics_enabled: 'false' }
          it { is_expected.to include integration_http_analytics_sample_rate: '1.0' }
          it { is_expected.to include integration_http_service_name: 'my-http' }
          it { is_expected.to include integration_http_distributed_tracing: 'true' }
          it { is_expected.to include integration_http_split_by_domain: 'false' }
        end

        context 'with a complex setting value' do
          let(:options) { { service_name: Class.new } }

          it 'converts to a string' do
            is_expected.to include integration_http_service_name: start_with('#<Class:')
          end
        end
      end

      context 'with MRI' do
        before { skip unless PlatformHelpers.mri? }

        it { is_expected.to include vm: start_with('ruby') }
      end

      context 'with JRuby' do
        before { skip unless PlatformHelpers.jruby? }

        it { is_expected.to include vm: start_with('jruby') }
      end

      context 'with TruffleRuby' do
        before { skip unless PlatformHelpers.truffleruby? }

        it { is_expected.to include vm: start_with('truffleruby') }
      end
    end
  end
end
