require 'spec_helper'

require 'datadog/core/diagnostics/environment_logger'
require 'ddtrace/transport/io'

RSpec.describe Datadog::Core::Diagnostics::EnvironmentLogger do
  subject(:env_logger) { described_class }

  # Reading DD_AGENT_HOST allows this to work in CI
  let(:agent_hostname) { ENV['DD_AGENT_HOST'] || '127.0.0.1' }
  let(:agent_port) { ENV['DD_TRACE_AGENT_PORT'] || 8126 }

  before do
    allow(DateTime).to receive(:now).and_return(DateTime.new(2020))

    # Resets "only-once" execution pattern of `log!`
    env_logger.instance_variable_set(:@executed, nil)

    Datadog.configuration.reset!
  end

  describe '#log!' do
    subject(:log!) { env_logger.log!([response]) }

    let(:logger) do
      log!
      tracer_logger
    end

    let(:response) { instance_double(Datadog::Transport::Response, ok?: true) }
    let(:tracer_logger) { instance_double(Datadog::Core::Logger) }

    before do
      allow(Datadog).to receive(:logger).and_return(tracer_logger)
      allow(tracer_logger).to receive(:debug?).and_return true
      allow(tracer_logger).to receive(:debug)
      allow(tracer_logger).to receive(:info)
      allow(tracer_logger).to receive(:warn)
      allow(tracer_logger).to receive(:error)
    end

    it 'with a default tracer settings' do
      expect(logger).to have_received(:info).with start_with('DATADOG CONFIGURATION') do |msg|
        json = JSON.parse(msg.partition('-')[2].strip)
        expect(json).to include(
          'date' => '2020-01-01T00:00:00+00:00',
          'debug' => false,
          'health_metrics_enabled' => false,
          'lang' => 'ruby',
          'lang_version' => match(/[23]\./),
          'os_name' => (include('x86_64').or include('i686').or include('aarch64').or include('arm')),
          'runtime_metrics_enabled' => false,
          'version' => DDTrace::VERSION::STRING,
          'vm' => be_a(String),
          'service' => be_a(String),
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

    # should this context be in tracing?
    context 'with agent error' do
      before { allow(tracer_logger).to receive(:warn) }

      let(:response) { Datadog::Transport::InternalErrorResponse.new(ZeroDivisionError.new('msg')) }

      it do
        expect(logger).to have_received(:warn).with start_with('DATADOG DIAGNOSTIC') do |msg|
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
        expect_any_instance_of(Datadog::Core::Diagnostics::EnvironmentCollector).to receive(:collect!).and_raise
      end

      it 'rescues error and logs exception' do
        expect(logger).to have_received(:warn).with start_with('Failed to collect environment information')
      end
    end
  end

  describe Datadog::Core::Diagnostics::EnvironmentCollector do
    describe '#collect!' do
      subject(:collect!) { collector.collect!([response]) }

      let(:collector) { described_class.new }
      let(:response) { instance_double(Datadog::Transport::Response, ok?: true) }

      it 'with a default tracer' do
        is_expected.to include(
          agent_error: nil,
          agent_url: start_with("http://#{agent_hostname}:#{agent_port}?timeout="),
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
          os_name: (include('x86_64').or include('i686').or include('aarch64').or include('arm')),
          partial_flushing_enabled: false,
          priority_sampling_enabled: false,
          runtime_metrics_enabled: false,
          sample_rate: nil,
          sampling_rules: nil,
          service: be_a(String),
          tags: nil,
          version: DDTrace::VERSION::STRING,
          vm: be_a(String),
          profiling_enabled: false,
        )
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
        before do
          Datadog.configure do |c|
            c.diagnostics.debug = true
            c.logger.instance = Datadog::Core::Logger.new(StringIO.new)
          end
        end

        it { is_expected.to include debug: true }
      end

      context 'with runtime metrics enabled' do
        before { Datadog.configure { |c| c.runtime_metrics.enabled = true } }

        after { Datadog.configuration.runtime_metrics.reset! }

        it { is_expected.to include runtime_metrics_enabled: true }
      end

      context 'with health metrics enabled' do
        before { Datadog.configure { |c| c.diagnostics.health_metrics.enabled = true } }

        it { is_expected.to include health_metrics_enabled: true }
      end

      context 'with MRI' do
        before { skip('Spec only runs on MRI') unless PlatformHelpers.mri? }

        it { is_expected.to include vm: start_with('ruby') }
      end

      context 'with JRuby' do
        before { skip('Spec only runs on JRuby') unless PlatformHelpers.jruby? }

        it { is_expected.to include vm: start_with('jruby') }
      end

      context 'with TruffleRuby' do
        before { skip('Spec only runs on TruffleRuby') unless PlatformHelpers.truffleruby? }

        it { is_expected.to include vm: start_with('truffleruby') }
      end
    end

    # add collect_errors tests?
  end
end
