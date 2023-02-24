require 'spec_helper'

require 'benchmark'
require 'ddtrace'

RSpec.describe 'Telemetry Benchmark' do
  let(:enabled) { 'true' }

  around do |example|
    ClimateControl.modify(Datadog::Core::Telemetry::Ext::ENV_ENABLED => enabled) do
      example.run
    end
  end

  before do
    skip('Benchmark results not currently captured in CI') if ENV.key?('CI')

    # Create double to swallow log output
    logger = double(Datadog::Core::Logger)
    allow(logger).to receive(:debug)
    allow(logger).to receive(:info)
    allow(logger).to receive(:warn)
    allow(logger).to receive(:error)
    allow(Datadog).to receive(:logger).and_return(logger)
  end

  include Benchmark

  context 'telemetry disabled' do
    let(:enabled) { 'false' }

    it do
      Benchmark.benchmark(Benchmark::CAPTION, 30, Benchmark::FORMAT) do |x|
        x.report('#configure') { Datadog.configure {} }
        x.report('#integration_change') { Datadog.configure { |c| c.tracing.instrument :rake } }
        x.report('#close') { Datadog::Tracing.shutdown! }
      end
    end
  end

  context 'telemetry enabled' do
    let(:enabled) { 'true' }

    it do
      Benchmark.benchmark(Benchmark::CAPTION, 30, Benchmark::FORMAT) do |x|
        x.report('#configure') { Datadog.configure {} }
        x.report('#integration_change') { Datadog.configure { |c| c.tracing.instrument :rake } }
        x.report('#close') { Datadog::Tracing.shutdown! }
      end
    end
  end
end
