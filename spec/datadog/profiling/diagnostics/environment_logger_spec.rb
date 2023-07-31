require 'spec_helper'
require 'datadog/profiling/diagnostics/environment_logger'
require 'ddtrace/transport/io'

RSpec.describe Datadog::Profiling::Diagnostics::EnvironmentLogger do
  subject(:env_logger) { described_class }

  before do
    # Resets "only-once" execution pattern of `log!`
    env_logger.instance_variable_set(:@executed, nil)

    Datadog.configuration.reset!
  end

  describe '#log!' do
    subject(:log!) { env_logger.log! }

    let(:logger) do
      log!
      tracer_logger
    end

    let(:tracer_logger) { instance_double(Datadog::Core::Logger) }

    before do
      allow(env_logger).to receive(:rspec?). and_return(false) # Allow rspec to log for testing purposes
      allow(Datadog).to receive(:logger).and_return(tracer_logger)
      allow(tracer_logger).to receive(:debug?).and_return true
      allow(tracer_logger).to receive(:debug)
      allow(tracer_logger).to receive(:info)
      # allow(tracer_logger).to receive(:warn)
      # allow(tracer_logger).to receive(:error)
    end

    it 'with default profiling settings' do
      expect(logger).to have_received(:info).with start_with('DATADOG CONFIGURATION - PROFILING') do |msg|
        json = JSON.parse(msg.partition('- PROFILING -')[2].strip)
        expect(json).to match(
          'profiling_enabled' => false,
        )
      end
    end

    context 'with multiple invocations' do
      it 'executes only once' do
        env_logger.log!
        env_logger.log!

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
          allow(env_logger).to receive(:rspec?). and_return(true) # Prevent rspec from logging
        end

        it { expect(logger).to_not have_received(:info) }
      end

      context 'with explicit setting' do
        before do
          Datadog.configure { |c| c.diagnostics.startup_logs.enabled = true }
        end

        it { expect(logger).to have_received(:info) }
      end
    end
  end

  describe Datadog::Profiling::Diagnostics::EnvironmentCollector do
    describe '#collect!' do
      subject(:collect!) { collector.collect! }

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
