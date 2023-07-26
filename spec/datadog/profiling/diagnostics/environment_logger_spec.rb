require 'spec_helper'
require 'datadog/profiling/diagnostics/environment_logger'
require 'ddtrace/transport/io'

RSpec.describe Datadog::Profiling::Diagnostics::EnvironmentLogger do
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

  describe '#prefix' do
    it 'for profiling settings' do
      expect(logger).to have_received(:info).with include('PROFILING')
    end
  end

  describe Datadog::Profiling::Diagnostics::EnvironmentCollector do
    describe '#collect!' do
      subject(:collect!) { collector.collect!([response]) }

      let(:collector) { described_class.new }
      let(:response) { instance_double(Datadog::Transport::Response, ok?: true) }

      it 'with a default tracer' do
        is_expected.to match(
          profiling_enabled: false
        )
      end

      context 'with profiling enabled' do
        before do
          allow_any_instance_of(Datadog::Profiling::Profiler).to receive(:start) if PlatformHelpers.mri?
          Datadog.configure { |c| c.profiling.enabled = true }
        end

        it { is_expected.to include profiling_enabled: true }
      end
    end
  end
end
