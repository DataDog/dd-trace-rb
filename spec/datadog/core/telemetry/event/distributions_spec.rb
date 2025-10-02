require 'spec_helper'

require 'datadog/core/telemetry/event/distributions'
require 'datadog/core/telemetry/metric'

RSpec.describe Datadog::Core::Telemetry::Event::Distributions do
  let(:id) { double('seq_id') }
  let(:event) { described_class.new }

  let(:event) { described_class.new(namespace, metrics) }

  let(:namespace) { 'general' }
  let(:metric_name) { 'request_duration' }
  let(:metric) do
    Datadog::Core::Telemetry::Metric::Distribution.new(metric_name, tags: {status: '200'})
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
end
