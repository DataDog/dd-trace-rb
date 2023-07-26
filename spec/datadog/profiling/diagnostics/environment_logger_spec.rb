require 'spec_helper'
require 'datadog/profiling/diagnostics/environment_logger'
require 'ddtrace/transport/io'

RSpec.describe Datadog::Profiling::Diagnostics::ProfilingEnvironmentCollector do
    describe '#collect!' do
      subject(:collect!) { collector.collect!([response]) }

      let(:collector) { described_class.new }
      let(:response) { instance_double(Datadog::Transport::Response, ok?: true) }

      it 'with a default tracer' do
        is_expected.to include profiling_enabled: false
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
