require 'spec_helper'

require 'logger'
require 'json'

require 'datadog/core/metrics/logging'
require 'datadog/core/metrics/client'

RSpec.describe Datadog::Core::Metrics::Logging::Adapter do
  subject(:adapter) { described_class.new(logger) }

  let(:logger) { instance_double(Logger) }

  def have_received_json_metric(expected_hash)
    have_received(:info) do |msg|
      json = JSON.parse(msg)
      expect(json).to include('stat' => expected_hash[:stat])
      expect(json).to include('type' => expected_hash[:type])
      expect(json).to include('value' => expected_hash[:value]) if expected_hash.key?(:value)
      expect(json).to include('options' => hash_including(expected_hash[:options]))
    end
  end

  describe '#initialize' do
    context 'by default' do
      subject(:adapter) { described_class.new }

      describe '#logger' do
        subject(:logger) { adapter.logger }

        it { expect(logger.level).to be(Logger::INFO) }
        it { expect(logger.instance_variable_get(:@logdev).dev).to eq($stdout) }
      end
    end

    context 'given a logger' do
      subject(:adapter) { described_class.new(logger) }

      let(:logger) { instance_double(Logger) }

      it { expect(adapter.logger).to be logger }
    end
  end

  describe '#count' do
    subject(:count) { adapter.count(stat, value, options) }

    let(:stat) { :my_stat }
    let(:value) { 100 }
    let(:options) { { tags: ['foo:bar'] } }

    before { allow(logger).to receive(:info) }

    it 'sends a JSON-encoded metric to the logger' do
      count
      expect(logger).to have_received_json_metric(
        stat: stat.to_s,
        type: 'count',
        value: value,
        options: { 'tags' => array_including(options[:tags]) }
      )
    end
  end

  describe '#distribution' do
    subject(:distribution) { adapter.distribution(stat, value, options) }

    let(:stat) { :my_stat }
    let(:value) { 100 }
    let(:options) { { tags: ['foo:bar'] } }

    before { allow(logger).to receive(:info) }

    it 'sends a JSON-encoded metric to the logger' do
      distribution
      expect(logger).to have_received_json_metric(
        stat: stat.to_s,
        type: 'distribution',
        value: value,
        options: { 'tags' => array_including(options[:tags]) }
      )
    end
  end

  describe '#increment' do
    subject(:increment) { adapter.increment(stat, options) }

    let(:stat) { :my_stat }
    let(:options) { { tags: ['foo:bar'] } }

    before { allow(logger).to receive(:info) }

    it 'sends a JSON-encoded metric to the logger' do
      increment
      expect(logger).to have_received_json_metric(
        stat: stat.to_s,
        type: 'increment',
        options: { 'tags' => array_including(options[:tags]) }
      )
    end
  end

  describe '#gauge' do
    subject(:gauge) { adapter.gauge(stat, value, options) }

    let(:stat) { :my_stat }
    let(:value) { 100 }
    let(:options) { { tags: ['foo:bar'] } }

    before { allow(logger).to receive(:info) }

    it 'sends a JSON-encoded metric to the logger' do
      gauge
      expect(logger).to have_received_json_metric(
        stat: stat.to_s,
        type: 'gauge',
        value: value,
        options: { 'tags' => array_including(options[:tags]) }
      )
    end
  end

  context 'when used in Datadog::Metrics' do
    subject(:metrics) { Datadog::Core::Metrics::Client.new(statsd: adapter) }

    describe 'and #count is sent' do
      subject(:count) { metrics.count(stat, value, options) }

      let(:stat) { :my_stat }
      let(:value) { 100 }
      let(:options) { { tags: ['foo:bar'] } }

      before do
        allow(adapter).to receive(:count)
        count
      end

      it 'forwards the message to the adapter' do
        expect(adapter).to have_received(:count)
          .with(
            stat,
            value,
            hash_including(tags: array_including(options[:tags]))
          )
      end
    end
  end
end
