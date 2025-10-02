require 'spec_helper'

require 'datadog/core/telemetry/event/generate_metrics'
require 'datadog/core/telemetry/metric'

RSpec.describe Datadog::Core::Telemetry::Event::GenerateMetrics do
  let(:id) { double('seq_id') }
  let(:event) { described_class.new }

  let(:event) { described_class.new(namespace, metrics) }

  let(:namespace) { 'general' }
  let(:metric_name) { 'request_count' }
  let(:metric) do
    Datadog::Core::Telemetry::Metric::Count.new(metric_name, tags: {status: '200'})
  end
  let(:metrics) { [metric] }

  let(:expected_metric_series) { [metric.to_h] }

  describe '.payload' do
    subject(:payload) { event.payload }

    it do
      is_expected.to eq(
        {
          namespace: namespace,
          series: expected_metric_series
        }
      )
    end
  end

  it 'all events to be the same' do
    events = [
      described_class.new('namespace', [Datadog::Core::Telemetry::Metric::Count.new('name', tags: {val: '1'})]),
      described_class.new('namespace', [Datadog::Core::Telemetry::Metric::Count.new('name', tags: {val: '1'})]),
    ]

    expect(events.uniq).to have(1).item
  end

  it 'all events to be different' do
    events = [
      described_class.new('namespace', [Datadog::Core::Telemetry::Metric::Count.new('name', tags: {val: '1'})]),
      described_class.new('nospace', [Datadog::Core::Telemetry::Metric::Count.new('name', tags: {val: '1'})]),
      described_class.new('namespace', [Datadog::Core::Telemetry::Metric::Count.new('name', tags: {val: '2'})]),
      described_class.new('namespace', []),

    ]

    expect(events.uniq).to eq(events)
  end
end
