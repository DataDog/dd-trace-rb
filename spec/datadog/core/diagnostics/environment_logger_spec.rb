# frozen_string_literal: true

require 'spec_helper'
require 'datadog/core/diagnostics/environment_logger'
require 'datadog/tracing/transport/io'
require 'datadog/profiling/profiler'

RSpec.describe Datadog::Core::Diagnostics::EnvironmentLogger do
  subject(:env_logger) { described_class }

  before do
    allow(Time).to receive(:now).and_return(Time.new(2020))

    # Resets "only-once" execution pattern of `collect_and_log!`
    env_logger.instance_variable_set(:@executed, nil)

    Datadog.configuration.reset!
  end

  describe '#collect_and_log!' do
    subject(:collect_and_log!) { env_logger.collect_and_log! }

    let(:logger) { instance_double(Datadog::Core::Logger) }
    let(:expected_logger_result) do
      {
        'date' => '2020-01-01T00:00:00Z',
        'os_name' => (include('x86_64').or include('i686').or include('aarch64').or include('arm')),
        'version' => Datadog::VERSION::STRING,
        'lang' => 'ruby',
        'lang_version' => match(/[23]\./),
        'env' => nil,
        'service' => be_a(String),
        'dd_version' => nil,
        'debug' => false,
        'tags' => nil,
        'runtime_metrics_enabled' => false,
        'vm' => be_a(String),
        'health_metrics_enabled' => false,
      }
    end

    before do
      allow(env_logger).to receive(:rspec?).and_return(false) # Allow rspec to log for testing purposes
      allow(Datadog).to receive(:logger).and_return(logger)
      allow(logger).to receive(:debug?).and_return(true)
      allow(logger).to receive(:debug)
      allow(logger).to receive(:info)
      allow(logger).to receive(:warn)
    end

    it 'with default core settings' do
      collect_and_log!
      expect(logger).to have_received(:info).with start_with('DATADOG CONFIGURATION - CORE') do |msg|
        json = JSON.parse(msg.partition('- CORE -')[2].strip)
        expect(json).to match(expected_logger_result)
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
        before do
          allow(env_logger).to receive(:rspec?).and_return(true) # Prevent rspec from logging
        end

        it { expect(logger).to_not have_received(:info) }
      end

      context 'with explicit setting' do
        before do
          allow(Datadog.configuration.diagnostics.startup_logs).to receive(:enabled).and_return(true)
        end

        it do
          collect_and_log!
          expect(logger).to have_received(:info).with(/DATADOG CONFIGURATION - CORE -/).once
        end
      end
    end

    context 'with error collecting information' do
      before do
        allow(logger).to receive(:warn)
        expect(Datadog::Core::Diagnostics::EnvironmentCollector).to receive(:collect_config!).and_raise
      end

      it 'rescues error and logs exception' do
        collect_and_log!
        expect(logger).to have_received(:warn).with start_with('Failed to collect core environment information')
      end
    end

    context 'when extra fields are provided' do
      let(:extra_fields) { { hello: 123, world: '456' } }

      subject(:collect_and_log!) { env_logger.collect_and_log!(extra_fields) }

      it 'includes the base fields' do
        collect_and_log!
        expect(logger).to have_received(:info).with start_with('DATADOG CONFIGURATION - CORE') do |msg|
          json = JSON.parse(msg.partition('- CORE -')[2].strip)
          expect(json).to include(expected_logger_result)
        end
      end

      it 'includes the extra fields' do
        collect_and_log!
        expect(logger).to have_received(:info).with start_with('DATADOG CONFIGURATION - CORE') do |msg|
          json = JSON.parse(msg.partition('- CORE -')[2].strip)
          expect(json).to include(
            'hello' => 123,
            'world' => '456',
          )
        end
      end
    end
  end

  describe Datadog::Core::Diagnostics::EnvironmentCollector do
    describe '#collect_config!' do
      subject(:collect_config!) { collector.collect_config! }

      let(:collector) { described_class }

      it 'with a default core' do
        is_expected.to match(
          date: '2020-01-01T00:00:00Z',
          os_name: (include('x86_64').or include('i686').or include('aarch64').or include('arm')),
          version: Datadog::VERSION::STRING,
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
        let(:version) { double('version') }

        before { allow(Datadog.configuration).to receive(:version).and_return(version) }

        it { is_expected.to include dd_version: version }
      end

      context 'with env configured' do
        let(:env) { double('env') }

        before { allow(Datadog.configuration).to receive(:env).and_return(env) }

        it { is_expected.to include env: env }
      end

      context 'with service configured' do
        let(:service) { 'service' }

        before { allow(Datadog.configuration).to receive(:service).and_return(service) }

        it { is_expected.to include service: service }
      end

      context 'with debug enabled' do
        before do
          expect(Datadog.configuration.diagnostics).to receive(:debug).and_return(true)
          allow(Datadog.configuration.logger).to receive(:instance).and_return(Datadog::Core::Logger.new(StringIO.new))
        end

        it { is_expected.to include debug: true }
      end

      context 'with tags configured' do
        before { expect(Datadog.configuration).to receive(:tags).and_return({ 'k1' => 'v1', 'k2' => 'v2' }) }

        it { is_expected.to include tags: 'k1:v1,k2:v2' }
      end

      context 'with runtime metrics enabled' do
        before { expect(Datadog.configuration.runtime_metrics).to receive(:enabled).and_return(true) }

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
        before { expect(Datadog.configuration.health_metrics).to receive(:enabled).and_return(true) }

        it { is_expected.to include health_metrics_enabled: true }
      end
    end
  end
end
