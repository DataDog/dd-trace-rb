require 'spec_helper'
require 'datadog/profiling/diagnostics/environment_logger'
require 'ddtrace/transport/io'

RSpec.describe Datadog::Profiling::Diagnostics::EnvironmentLogger do
  subject(:env_logger) { described_class }

  before do
    # Resets "only-once" execution pattern of `collect_and_log!`
    env_logger.instance_variable_set(:@executed, nil)

    Datadog.configuration.reset!
  end

  describe '#collect_and_log!' do
    subject(:collect_and_log!) { env_logger.collect_and_log! }

    let(:logger) { instance_double(Datadog::Core::Logger) }

    # let(:logger) do
    #   collect_and_log!
    #   logger
    # end

    # let(:logger) { instance_double(Datadog::Core::Logger) }

    before do
      allow(env_logger).to receive(:rspec?).and_return(false) # Allow rspec to log for testing purposes
      allow(Datadog).to receive(:logger).and_return(logger)
      allow(logger).to receive(:debug?).and_return true
      allow(logger).to receive(:debug)
      allow(logger).to receive(:info)
    end

    it 'with default profiling settings' do
      collect_and_log!
      expect(logger).to have_received(:info).with start_with('DATADOG CONFIGURATION - PROFILING') do |msg|
        json = JSON.parse(msg.partition('- PROFILING -')[2].strip)
        expect(json).to match(
          'profiling_enabled' => false,
        )
      end
    end

    context 'with multiple invocations' do
      it 'executes only once' do
        env_logger.collect_and_log!
        env_logger.collect_and_log!

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
        before do
          allow(env_logger).to receive(:rspec?).and_return(true) # Prevent rspec from logging
        end

        it do
          collect_and_log!
          expect(logger).to_not have_received(:info)
        end
      end

      context 'with explicit setting' do
        before do
          Datadog.configure { |c| c.diagnostics.startup_logs.enabled = true }
        end

        it do
          collect_and_log!
          expect(logger).to have_received(:info).with(/DATADOG CONFIGURATION - PROFILING -/).once
        end
      end
    end
  end

  describe Datadog::Profiling::Diagnostics::EnvironmentCollector do
    describe '#collect_config!' do
      subject(:collect_config!) { collector.collect_config! }

      let(:collector) { described_class }

      it 'with a default profiler' do
        is_expected.to match(
          profiling_enabled: false
        )
      end

      context 'with profiling enabled' do
        before do
          # allow_any_instance_of(Datadog::Profiling::Profiler).to receive(:start) if PlatformHelpers.mri?
          Datadog.configure { |c| c.profiling.enabled = true }
        end

        it { is_expected.to include profiling_enabled: true }
      end
    end
  end
end
