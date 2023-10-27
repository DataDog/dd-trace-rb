require 'spec_helper'

require 'datadog/core/telemetry/metric_worker'

RSpec.describe Datadog::Core::Telemetry::MetricWorker do
  subject(:metric_worker) do
    described_class.new(enabled: enabled, heartbeat_interval_seconds: heartbeat_interval_seconds, &block)
  end

  let(:enabled) { true }
  let(:heartbeat_interval_seconds) { 1.2 }
  let(:block) { proc {} }

  after do
    metric_worker.stop(true)
    metric_worker.join
  end

  describe '.new' do
    context 'when using default settings' do
      subject(:metric_worker) { described_class.new(heartbeat_interval_seconds: heartbeat_interval_seconds, &block) }
      it do
        is_expected.to have_attributes(
          enabled?: true,
          loop_base_interval: 1.2, # seconds
          task: block
        )
      end
    end

    context 'when enabled' do
      let(:enabled) { true }

      it do
        metric_worker

        try_wait_until { metric_worker.running? }
        expect(metric_worker).to have_attributes(
          run_async?: true,
          running?: true,
          started?: true
        )
      end
    end
  end
end
