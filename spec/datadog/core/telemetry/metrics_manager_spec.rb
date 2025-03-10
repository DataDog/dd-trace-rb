require 'spec_helper'

require 'datadog/core/telemetry/metrics_manager'

RSpec.describe Datadog::Core::Telemetry::MetricsManager do
  subject(:manager) { described_class.new(aggregation_interval: interval, enabled: enabled) }

  def collections
    manager.instance_variable_get(:@collections)
  end

  def first_collection
    collections.values.first
  end

  let(:interval) { 10 }
  let(:enabled) { true }
  let(:namespace) { 'namespace' }
  let(:metric_name) { 'metric_name' }
  let(:value) { 5 }
  let(:tags) { { tag1: 'val1', tag2: 'val2' } }
  let(:common) { true }

  describe '#inc' do
    subject(:inc) { manager.inc(namespace, metric_name, value, tags: tags, common: common) }

    it 'creates a new collection' do
      expect { inc }.to change(collections, :size).from(0).to(1)
      expect(first_collection.namespace).to eq(namespace)
      expect(first_collection.interval).to eq(interval)
    end

    it 'forwards the action to the collection' do
      collection = double(:collection)
      expect(Datadog::Core::Telemetry::MetricsCollection).to receive(:new).and_return(collection)
      expect(collection).to receive(:inc).with(metric_name, value, tags: tags, common: common)

      inc
    end

    context 'with different namespaces' do
      it 'creates collection per namespace' do
        inc

        expect { manager.inc('another_namespace', metric_name, value, tags: tags, common: common) }
          .to change(collections, :size).from(1).to(2)
      end
    end

    context 'when disabled' do
      let(:enabled) { false }

      it 'does nothing' do
        expect { inc }.not_to change(collections, :size)
      end
    end
  end

  describe '#dec' do
    subject(:dec) { manager.dec(namespace, metric_name, value, tags: tags, common: common) }

    it 'creates a new collection' do
      expect { dec }.to change(collections, :size).from(0).to(1)
      expect(first_collection.namespace).to eq(namespace)
      expect(first_collection.interval).to eq(interval)
    end

    it 'forwards the action to the collection' do
      collection = double(:collection)
      expect(Datadog::Core::Telemetry::MetricsCollection).to receive(:new).and_return(collection)
      expect(collection).to receive(:dec).with(metric_name, value, tags: tags, common: common)

      dec
    end

    context 'when disabled' do
      let(:enabled) { false }

      it 'does nothing' do
        expect { dec }.not_to change(collections, :size)
      end
    end
  end

  describe '#gauge' do
    subject(:gauge) { manager.gauge(namespace, metric_name, value, tags: tags, common: common) }

    it 'creates a new collection' do
      expect { gauge }.to change(collections, :size).from(0).to(1)
      expect(first_collection.namespace).to eq(namespace)
      expect(first_collection.interval).to eq(interval)
    end

    it 'forwards the action to the collection' do
      collection = double(:collection)
      expect(Datadog::Core::Telemetry::MetricsCollection).to receive(:new).and_return(collection)
      expect(collection).to receive(:gauge).with(metric_name, value, tags: tags, common: common)

      gauge
    end

    context 'with different namespaces' do
      it 'creates collection per namespace' do
        gauge

        expect { manager.gauge('another_namespace', metric_name, value, tags: tags, common: common) }
          .to change(collections, :size).from(1).to(2)
      end
    end

    context 'when disabled' do
      let(:enabled) { false }

      it 'does nothing' do
        expect { gauge }.not_to change(collections, :size)
      end
    end
  end

  describe '#rate' do
    subject(:rate) { manager.rate(namespace, metric_name, value, tags: tags, common: common) }

    it 'creates a new collection' do
      expect { rate }.to change(collections, :size).from(0).to(1)
      expect(first_collection.namespace).to eq(namespace)
      expect(first_collection.interval).to eq(interval)
    end

    it 'forwards the action to the collection' do
      collection = double(:collection)
      expect(Datadog::Core::Telemetry::MetricsCollection).to receive(:new).and_return(collection)
      expect(collection).to receive(:rate).with(metric_name, value, tags: tags, common: common)

      rate
    end

    context 'with different namespaces' do
      it 'creates collection per namespace' do
        rate

        expect { manager.rate('another_namespace', metric_name, value, tags: tags, common: common) }
          .to change(collections, :size).from(1).to(2)
      end
    end

    context 'when disabled' do
      let(:enabled) { false }

      it 'does nothing' do
        expect { rate }.not_to change(collections, :size)
      end
    end
  end

  describe '#distribution' do
    subject(:distribution) { manager.distribution(namespace, metric_name, value, tags: tags, common: common) }

    it 'creates a new collection' do
      expect { distribution }.to change(collections, :size).from(0).to(1)
      expect(first_collection.namespace).to eq(namespace)
      expect(first_collection.interval).to eq(interval)
    end

    it 'forwards the action to the collection' do
      collection = double(:collection)
      expect(Datadog::Core::Telemetry::MetricsCollection).to receive(:new).and_return(collection)
      expect(collection).to receive(:distribution).with(metric_name, value, tags: tags, common: common)

      distribution
    end

    context 'with different namespaces' do
      it 'creates collection per namespace' do
        distribution

        expect { manager.distribution('another_namespace', metric_name, value, tags: tags, common: common) }
          .to change(collections, :size).from(1).to(2)
      end
    end

    context 'when disabled' do
      let(:enabled) { false }

      it 'does nothing' do
        expect { distribution }.not_to change(collections, :size)
      end
    end
  end

  describe '#flush!' do
    subject(:flush!) { manager.flush! }

    it 'forwards flush to the collections' do
      events = [double(:event)]

      collection = double(:collection)
      expect(Datadog::Core::Telemetry::MetricsCollection).to receive(:new).and_return(collection)
      expect(collection).to receive(:inc)
      expect(collection).to receive(:flush!).and_return(events)

      manager.inc(namespace, metric_name, value, tags: tags)
      expect(flush!).to eq(events)
    end

    context 'when disabled' do
      let(:enabled) { false }

      it 'does nothing' do
        expect(Datadog::Core::Telemetry::MetricsCollection).to_not receive(:new)

        expect(flush!).to eq([])
      end
    end

    context 'concurrently creating and flushing namespaces' do
      it 'flushes all metrics' do
        mutex = Mutex.new

        threads_count = 5
        metrics_per_thread = 3

        flushed_metrics_count = 0

        threads = Array.new(threads_count) do |n|
          Thread.new do
            metrics_per_thread.times do |i|
              manager.inc("namespace #{n}", "#{metric_name} #{i}", value, tags: tags)
            end
            events = manager.flush!

            mutex.synchronize do
              events.each do |event|
                flushed_metrics_count += event.payload[:series].count
              end
            end
          end
        end

        threads.each(&:join)

        expect(flushed_metrics_count).to eq(threads_count * metrics_per_thread)
      end
    end
  end

  describe '#disable!' do
    subject(:disable!) { manager.disable! }

    it 'disables the manager' do
      expect { disable! }.to change(manager, :enabled).from(true).to(false)
    end
  end
end
