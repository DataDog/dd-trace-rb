require 'spec_helper'

require 'datadog/core/telemetry/metric'

RSpec.describe Datadog::Core::Telemetry::Metric::Count do
  subject(:metric) { described_class.new('tests', { foo: :bar }) }
  let(:generate_metric_type) { 'generate-metrics' }

  describe '.request_type' do
    subject(:request_type) { metric.class.request_type }

    it { is_expected.to eq(generate_metric_type) }
  end

  describe '#update_value' do
    it 'increment values' do
      expect(metric.values).to be_nil
      metric.update_value(1)
      expect(metric.values).to_not be_nil
      expect(metric.values[0][1]).to eq 1
      metric.update_value(1)
      expect(metric.values[0][1]).to eq 2
    end

    it 'stores the timestamp as part of the values array' do
      expect(metric).to receive(:timestamp).and_return(1234)
      metric.update_value(1)
      expect(metric.values[0][0]).to eq 1234
    end
  end

  describe '#metric_type' do
    subject(:request_type) { metric.metric_type }

    it { is_expected.to eq('count') }
  end

  describe '#to_h' do
    it 'returns the metric information' do
      expect(metric).to receive(:timestamp).and_return(1234)
      metric.update_value(1)

      result = metric.to_h
      expected = { :common => true, :tags => ['foo:bar'], :type => 'count', :values => [[1234, 1]] }
      expect(result).to eq(expected)
    end
  end
end

RSpec.describe Datadog::Core::Telemetry::Metric::Rate do
  before do
    described_class.interval = 10.0
  end

  after do
    described_class.interval = nil
  end

  subject(:metric) { described_class.new('tests', { foo: :bar }) }
  let(:generate_metric_type) { 'generate-metrics' }

  describe '.request_type' do
    subject(:request_type) { metric.class.request_type }

    it { is_expected.to eq(generate_metric_type) }
  end

  describe '#update_value' do
    it 'calculate rate value using interval' do
      expect(metric.values).to be_nil
      metric.update_value(1)
      expect(metric.values).to_not be_nil
      expect(metric.values[0][1]).to eq 0.1
      metric.update_value(1)
      expect(metric.values[0][1]).to eq 0.2
    end

    it 'stores the timestamp as part of the values array' do
      expect(metric).to receive(:timestamp).and_return(1234)
      metric.update_value(1)
      expect(metric.values[0][0]).to eq 1234
    end
  end

  describe '#metric_type' do
    subject(:request_type) { metric.metric_type }

    it { is_expected.to eq('rate') }
  end

  describe '#to_h' do
    it 'returns the metric information' do
      expect(metric).to receive(:timestamp).and_return(1234)
      metric.update_value(1)

      result = metric.to_h
      expected = { :common => true, :tags => ['foo:bar'], :type => 'rate', :values => [[1234, 0.1]] }
      expect(result).to eq(expected)
    end
  end
end

RSpec.describe Datadog::Core::Telemetry::Metric::Gauge do
  subject(:metric) { described_class.new('tests', { foo: :bar }) }
  let(:generate_metric_type) { 'generate-metrics' }

  describe '.request_type' do
    subject(:request_type) { metric.class.request_type }

    it { is_expected.to eq(generate_metric_type) }
  end

  describe '#update_value' do
    it 'keeps the last value' do
      expect(metric.values).to be_nil
      metric.update_value(1)
      expect(metric.values).to_not be_nil
      expect(metric.values[0][1]).to eq 1
      metric.update_value(4)
      expect(metric.values[0][1]).to eq 4
    end

    it 'stores the timestamp as part of the values array' do
      expect(metric).to receive(:timestamp).and_return(1234)
      metric.update_value(1)
      expect(metric.values[0][0]).to eq 1234
    end
  end

  describe '#metric_type' do
    subject(:request_type) { metric.metric_type }

    it { is_expected.to eq('gauge') }
  end

  describe '#to_h' do
    it 'returns the metric information' do
      expect(metric).to receive(:timestamp).and_return(1234)
      metric.update_value(1)

      result = metric.to_h
      expected = { :common => true, :tags => ['foo:bar'], :type => 'gauge', :values => [[1234, 1]] }
      expect(result).to eq(expected)
    end
  end
end

RSpec.describe Datadog::Core::Telemetry::Metric::Distribution do
  subject(:metric) { described_class.new('tests', { foo: :bar }) }
  let(:distributions_metric_type) { 'distributions' }

  describe '.request_type' do
    subject(:request_type) { metric.class.request_type }

    it { is_expected.to eq(distributions_metric_type) }
  end

  describe '#update_value' do
    it 'agrregates all values' do
      expect(metric.values).to be_nil
      metric.update_value(1)
      expect(metric.values).to_not be_nil
      expect(metric.values).to eq [1]
      metric.update_value(4)
      expect(metric.values).to eq [1, 4]
    end
  end

  describe '#metric_type' do
    subject(:request_type) { metric.metric_type }

    it { is_expected.to eq('distributions') }
  end

  describe '#to_h' do
    it 'returns the metric information' do
      metric.update_value(1)

      result = metric.to_h
      expected = { :common => true, :tags => ['foo:bar'], :type => 'distributions', :values => [1] }
      expect(result).to eq(expected)
    end
  end
end
