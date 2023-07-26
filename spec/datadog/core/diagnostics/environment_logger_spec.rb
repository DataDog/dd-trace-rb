require 'spec_helper'
require 'datadog/core/diagnostics/environment_logger'
require 'ddtrace/transport/io'
require 'datadog/profiling/profiler'

RSpec.describe Datadog::Core::Diagnostics::EnvironmentLogging do
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
        expect(json).to match(
          'date' => '2020-01-01T00:00:00+00:00',
          'os_name' => (include('x86_64').or include('i686').or include('aarch64').or include('arm')),
          'version' => DDTrace::VERSION::STRING,
          'lang' => 'ruby',
          'lang_version' => match(/[23]\./),
          # 'env' => env,
          'service' => be_a(String),
          # 'dd_version' => dd_version,
          'debug' => false,
          # 'tags' => tags,
          'runtime_metrics_enabled' => false,
          'vm' => be_a(String),
          'health_metrics_enabled' => false,
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

  describe Datadog::Core::Diagnostics::EnvironmentLogger do
    describe '#prefix' do
      it 'for core settings' do
        expect(logger).to have_received(:info).with include('CORE')
      end
    end
  end

  describe Datadog::Core::Diagnostics::EnvironmentCollector do
    describe '#collect!' do
      subject(:collect!) { collector.collect!([response]) }

      let(:collector) { described_class.new }
      let(:response) { instance_double(Datadog::Transport::Response, ok?: true) }

      it 'with a default tracer' do
        is_expected.to match(
          date: '2020-01-01T00:00:00+00:00',
          os_name: (include('x86_64').or include('i686').or include('aarch64').or include('arm')),
          version: DDTrace::VERSION::STRING,
          lang: 'ruby',
          lang_version: match(/[23]\./),
          env: nil,
          service: be_a(String),
          dd_version: nil,
          debug: false,
          tags: nil,
          runtime_metrics_enabled: false,
          vm: be_a(String),
          health_metrics_enabled: false
        )
      end

      context 'with version configured' do
        before { Datadog.configure { |c| c.version = '1.2' } }

        it { is_expected.to include dd_version: '1.2' }
      end

      context 'with env configured' do
        before { Datadog.configure { |c| c.env = 'env' } }

        it { is_expected.to include env: 'env' }
      end

      context 'with service configured' do
        before { Datadog.configure { |c| c.service = 'svc' } }

        it { is_expected.to include service: 'svc' }
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

      context 'with tags configured' do
        before { Datadog.configure { |c| c.tags = { 'k1' => 'v1', 'k2' => 'v2' } } }

        it { is_expected.to include tags: 'k1:v1,k2:v2' }
      end

      context 'with runtime metrics enabled' do
        before { Datadog.configure { |c| c.runtime_metrics.enabled = true } }

        after { Datadog.configuration.runtime_metrics.reset! }

        it { is_expected.to include runtime_metrics_enabled: true }
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

      context 'with health metrics enabled' do
        before { Datadog.configure { |c| c.diagnostics.health_metrics.enabled = true } }

        it { is_expected.to include health_metrics_enabled: true }
      end
    end
  end
end
