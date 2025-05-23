require 'spec_helper'

require 'datadog/core/telemetry/event/generate_metrics'
require 'datadog/core/telemetry/metric'

RSpec.describe Datadog::Core::Telemetry::Event::GenerateMetrics do
  let(:id) { double('seq_id') }
  let(:event) { event_class.new }

  subject(:payload) { event.payload }

  let(:event_class) { described_class }
  let(:event) { event_class.new(namespace, metrics) }

  let(:namespace) { 'general' }
  let(:metric_name) { 'request_count' }
  let(:metric) do
    Datadog::Core::Telemetry::Metric::Count.new(metric_name, tags: { status: '200' })
  end
  let(:metrics) { [metric] }

  let(:expected_metric_series) { [metric.to_h] }

  it do
    is_expected.to eq(
      {
        namespace: namespace,
        series: expected_metric_series
      }
    )
  end

  it 'all events to be the same' do
    events =     [
      event_class.new('namespace', [Datadog::Core::Telemetry::Metric::Count.new('name', tags: { val: '1' })]),
      event_class.new('namespace', [Datadog::Core::Telemetry::Metric::Count.new('name', tags: { val: '1' })]),
    ]

    expect(events.uniq).to have(1).item
  end

  it 'all events to be different' do
    events =     [
      event_class.new('namespace', [Datadog::Core::Telemetry::Metric::Count.new('name', tags: { val: '1' })]),
      event_class.new('nospace', [Datadog::Core::Telemetry::Metric::Count.new('name', tags: { val: '1' })]),
      event_class.new('namespace', [Datadog::Core::Telemetry::Metric::Count.new('name', tags: { val: '2' })]),
      event_class.new('namespace', []),

    ]

    expect(events.uniq).to eq(events)
  end
end
