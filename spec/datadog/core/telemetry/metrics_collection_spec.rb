require 'spec_helper'

require 'datadog/core/telemetry/metrics_collection'

RSpec.describe Datadog::Core::Telemetry::MetricsCollection do
  subject(:collection) { described_class.new(namespace, aggregation_interval: interval) }

  def metrics
    collection.instance_variable_get(:@metrics)
  end

  def first_metric_value
    metrics.values.first.values.first.last
  end

  def distributions
    collection.instance_variable_get(:@distributions)
  end

  def first_distribution_values
    distributions.values.first.values
  end

  let(:namespace) { 'namespace' }
  let(:interval) { 10 }

  let(:metric_name) { 'metric_name' }
  let(:value) { 5 }
  let(:tags) { { tag1: 'val1', tag2: 'val2' } }
  let(:common) { true }

  describe '#inc' do
    subject(:inc) { collection.inc(metric_name, value, tags: tags, common: common) }

    it 'tracks the metric' do
      expect { inc }.to change { metrics.size }.by(1)
      expect(first_metric_value).to eq(value)
    end

    context 'incrementing again' do
      it 'aggregates the metric' do
        inc

        expect do
          collection.inc(metric_name, value, tags: tags, common: common)
        end.to change { metrics.size }.by(0)

        expect(first_metric_value).to eq(value * 2)
      end
    end

    context 'incrementing the same metric with different tags' do
      it 'tracks new metric' do
        inc

        expect do
          collection.inc(metric_name, value, tags: { tag1: 'val1', tag2: 'val3' }, common: common)
        end.to change { metrics.size }.by(1)
      end
    end

    context 'concurrent incrementing' do
      it 'aggregates all values in the same metric' do
        threads = Array.new(5) do
          Thread.new do
            collection.inc(metric_name, value, tags: tags, common: common)
          end
        end

        threads.each(&:join)

        expect(first_metric_value).to eq(value * threads.size)
      end
    end
  end

  describe '#dec' do
    subject(:dec) { collection.dec(metric_name, value, tags: tags, common: common) }

    it 'tracks the metric' do
      expect { dec }.to change { metrics.size }.by(1)
      expect(first_metric_value).to eq(-value)
    end

    context 'decrementing again' do
      it 'aggregates the metric' do
        dec

        expect do
          collection.dec(metric_name, value, tags: tags, common: common)
        end.to change { metrics.size }.by(0)

        expect(first_metric_value).to eq(-value * 2)
      end
    end

    context 'decrementing the same metric with different tags' do
      it 'tracks new metric' do
        dec

        expect do
          collection.dec(metric_name, value, tags: { tag1: 'val1', tag2: 'val3' }, common: common)
        end.to change { metrics.size }.by(1)
      end
    end

    context 'concurrent decrementing' do
      it 'aggregates all values in the same metric' do
        threads = Array.new(5) do
          Thread.new do
            collection.dec(metric_name, value, tags: tags, common: common)
          end
        end

        threads.each(&:join)

        expect(first_metric_value).to eq(-value * threads.size)
      end
    end
  end

  describe '#gauge' do
    subject(:gauge) { collection.gauge(metric_name, value, tags: tags, common: common) }

    it 'tracks the metric' do
      expect { gauge }.to change { metrics.size }.by(1)
      expect(first_metric_value).to eq(value)
    end

    context 'gauge again' do
      it 'aggregates the metric' do
        gauge

        expect do
          collection.gauge(metric_name, value + 2, tags: tags, common: common)
        end.to change { metrics.size }.by(0)

        expect(first_metric_value).to eq(value + 2)
      end
    end

    context 'gauge with different tags' do
      it 'tracks the new metric' do
        gauge

        expect do
          collection.gauge(metric_name, value, tags: { tag1: 'val1', tag2: 'val3' }, common: common)
        end.to change { metrics.size }.by(1)
      end
    end
  end

  describe '#rate' do
    subject(:rate) { collection.rate(metric_name, value, tags: tags, common: common) }

    it 'tracks the metric' do
      expect { rate }.to change { metrics.size }.by(1)
      expect(first_metric_value).to eq(value.to_f / interval)
    end

    context 'rate again' do
      it 'aggregates the metric' do
        rate

        expect do
          collection.rate(metric_name, value, tags: tags, common: common)
        end.to change { metrics.size }.by(0)

        expect(first_metric_value).to eq(1)
      end
    end

    context 'rate with different tags' do
      it 'tracks the new metric' do
        rate

        expect do
          collection.rate(metric_name, value, tags: { tag1: 'val1', tag2: 'val3' }, common: common)
        end.to change { metrics.size }.by(1)
      end
    end

    context 'concurrent rate' do
      it 'aggregates all values in the same metric' do
        threads = Array.new(5) do
          Thread.new do
            collection.rate(metric_name, value, tags: tags, common: common)
          end
        end

        threads.each(&:join)

        expect(first_metric_value).to eq(value.to_f * threads.size / interval)
      end
    end
  end

  describe '#distribution' do
    subject(:distribution) { collection.distribution(metric_name, value, tags: tags, common: common) }

    it 'tracks the metric' do
      expect { distribution }.to change { distributions.size }.by(1)
      expect(first_distribution_values).to eq([value])
    end

    context 'distribution again' do
      it 'aggregates the metric' do
        distribution

        expect do
          collection.distribution(metric_name, value, tags: tags, common: common)
        end.to change { distributions.size }.by(0)

        expect(first_distribution_values).to eq([value, value])
      end
    end

    context 'distribution with different tags' do
      it 'tracks the new metric' do
        distribution

        expect do
          collection.distribution(metric_name, value, tags: { tag1: 'val1', tag2: 'val3' }, common: common)
        end.to change { distributions.size }.by(1)
      end
    end

    context 'concurrent distribution' do
      it 'aggregates all values in the same metric' do
        threads = Array.new(5) do
          Thread.new do
            collection.distribution(metric_name, value, tags: tags, common: common)
          end
        end

        threads.each(&:join)

        expect(first_distribution_values).to eq([value] * threads.size)
      end
    end
  end

  describe '#flush!' do
    it 'flushes metrics' do
      collection.inc('metric_name', 5, tags: { tag1: 'val1', tag2: 'val2' }, common: true)
      collection.inc('metric_name', 5, tags: { tag1: 'val1', tag2: 'val3' }, common: true)

      events = collection.flush!
      expect(events).to have(1).item

      event = events.first
      expect(event).to be_a(Datadog::Core::Telemetry::Event::GenerateMetrics)
      payload = event.payload

      expect(payload.fetch(:namespace)).to eq(namespace)
      expect(payload.fetch(:series)).to have(2).items

      tags = payload[:series].map { |s| s[:tags] }.sort
      expect(tags).to eq([['tag1:val1', 'tag2:val2'], ['tag1:val1', 'tag2:val3']])

      expect(metrics.size).to eq(0)
    end

    it 'flushes distributions' do
      collection.distribution('metric_name', 5, tags: { tag1: 'val1', tag2: 'val2' }, common: true)
      collection.distribution('metric_name', 6, tags: { tag1: 'val1', tag2: 'val2' }, common: true)
      collection.distribution('metric_name', 5, tags: { tag1: 'val1', tag2: 'val3' }, common: true)
      collection.distribution('metric_name', 7, tags: { tag1: 'val1', tag2: 'val3' }, common: true)

      events = collection.flush!
      expect(events).to have(1).item

      event = events.first
      expect(event).to be_a(Datadog::Core::Telemetry::Event::Distributions)
      payload = event.payload

      expect(payload.fetch(:namespace)).to eq(namespace)
      expect(payload.fetch(:series)).to have(2).items

      tags = payload[:series].map { |s| s[:tags] }.sort
      expect(tags).to eq([['tag1:val1', 'tag2:val2'], ['tag1:val1', 'tag2:val3']])

      values = payload[:series].map { |s| s[:points] }.sort
      expect(values).to eq([[5, 6], [5, 7]])

      expect(distributions.size).to eq(0)
    end

    it 'does not lose metrics when running in multiple threads' do
      mutex = Mutex.new
      threads_count = 5
      metrics_count = 0

      threads = Array.new(threads_count) do |i|
        Thread.new do
          collection.inc("metric_name_#{i}", 5, tags: { tag1: 'val1', tag2: 'val2' }, common: true)

          events = collection.flush!

          collection.inc("metric_name_#{i}", 5, tags: { tag1: 'val1', tag2: 'val3' }, common: true)
          collection.distribution("metric_name_#{i}", 5, tags: { tag1: 'val1', tag2: 'val2' }, common: true)
          collection.distribution("metric_name_#{i}", 5, tags: { tag1: 'val1', tag2: 'val3' }, common: true)

          events += collection.flush!

          mutex.synchronize do
            events.each do |event|
              metrics_count += event.payload[:series].size
            end
          end
        end
      end

      threads.each(&:join)

      expect(metrics.size).to eq(0)
      expect(distributions.size).to eq(0)

      expect(metrics_count).to eq(4 * threads_count)
    end
  end
end
