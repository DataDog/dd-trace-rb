require 'spec_helper'

require 'ddtrace'
require 'ddtrace/buffer'

RSpec.describe Datadog::Buffer do
  subject(:buffer) { described_class.new(max_size) }
  let(:max_size) { 0 }

  def get_test_items(n = 1)
    Array.new(n) { double('item') }
  end

  describe '#initialize' do
    it { is_expected.to be_a_kind_of(described_class) }
  end

  describe '#push' do
    let(:output) { buffer.pop }

    context 'given no limit' do
      let(:items) { get_test_items(4) }
      let(:max_size) { 0 }

      it 'retains all items' do
        items.each { |t| buffer.push(t) }
        expect(output.length).to eq(4)
      end
    end

    context 'given a max size' do
      let(:items) { get_test_items(max_size + 1) }
      let(:max_size) { 3 }

      it 'does not exceed it' do
        items.each { |t| buffer.push(t) }

        expect(output.length).to eq(max_size)
        expect(output).to include(items.last)
      end
    end

    context 'when closed' do
      let(:max_size) { 0 }
      let(:items) { get_test_items(6) }

      let(:output) { buffer.pop }

      it 'retains items up to close' do
        items.first(4).each { |t| buffer.push(t) }
        buffer.close
        items.last(2).each { |t| buffer.push(t) }

        expect(output.length).to eq(4)
        expect(output).to_not include(*items.last(2))
      end
    end

    context 'thread safety' do
      subject(:push) { threads.each(&:join) }

      let(:max_size) { 500 }
      let(:thread_count) { 100 }
      let(:threads) do
        buffer

        Array.new(thread_count) do |i|
          Thread.new do
            sleep(rand / 1000)
            buffer.push([i])
          end
        end
      end

      let(:output) { buffer.pop }

      it 'does not have collisions' do
        push
        expect(output).to_not be nil
        expect(output.sort).to eq((0..thread_count - 1).map { |i| [i] })
      end
    end
  end

  describe '#length' do
    subject(:length) { buffer.length }

    context 'given no items' do
      it { is_expected.to eq(0) }
    end

    context 'given an item' do
      before { buffer.push([1]) }
      it { is_expected.to eq(1) }
    end
  end

  describe '#empty?' do
    subject(:empty?) { buffer.empty? }

    context 'given no items' do
      it { is_expected.to be true }
    end

    context 'given an item' do
      before { buffer.push([1]) }
      it { is_expected.to be false }
    end
  end

  describe '#pop' do
    subject(:pop) { buffer.pop }
    let(:items) { get_test_items(2) }

    before do
      items.each { |t| buffer.push(t) }
    end

    it do
      expect(pop.length).to eq(items.length)
      expect(pop).to include(*items)
      expect(buffer.empty?).to be true
    end
  end
end

RSpec.describe Datadog::TraceBuffer do
  include_context 'health metrics'

  subject(:buffer) { described_class.new(max_size) }
  let(:max_size) { 0 }

  def measure_traces_size(traces)
    traces.inject(Datadog::Runtime::ObjectSpace.estimate_bytesize(traces)) do |sum, trace|
      sum + measure_trace_size(trace)
    end
  end

  def measure_trace_size(trace)
    trace.inject(Datadog::Runtime::ObjectSpace.estimate_bytesize(trace)) do |sum, span|
      sum + Datadog::Runtime::ObjectSpace.estimate_bytesize(span)
    end
  end

  describe '#initialize' do
    it { is_expected.to be_a_kind_of(Datadog::Buffer) }
  end

  describe '#push' do
    let(:output) { buffer.pop }

    context 'given a max size' do
      let(:traces) { get_test_traces(max_size + 1) }
      let(:max_size) { 3 }

      it 'does not exceed it' do
        traces.each { |t| buffer.push(t) }

        expect(output.length).to eq(max_size)
        expect(output).to include(traces.last)

        # A trace will be dropped at random, except the trace
        # that triggered the overflow.
        dropped_traces = traces.reject { |t| output.include?(t) }

        expected_traces = traces - dropped_traces
        expected_spans = expected_traces.inject(0) { |sum, t| sum + t.length }

        # Calling #pop produces metrics:
        # Accept events for every #push, and one drop event for overflow
        expect(health_metrics).to have_received(:queue_accepted)
          .with(traces.length)
        expect(health_metrics).to have_received(:queue_accepted_lengths)
          .with(expected_spans)

        expect(health_metrics).to have_received(:queue_dropped)
          .with(dropped_traces.length)

        # Metrics for queue gauges.
        expect(health_metrics).to have_received(:queue_max_length)
          .with(max_size)
        expect(health_metrics).to have_received(:queue_spans)
          .with(expected_spans)
        expect(health_metrics).to have_received(:queue_length)
          .with(max_size)
      end
    end

    context 'when closed' do
      let(:max_size) { 0 }
      let(:traces) { get_test_traces(6) }

      let(:output) { buffer.pop }

      it 'retains items up to close' do
        traces.first(4).each { |t| buffer.push(t) }
        buffer.close
        traces.last(2).each { |t| buffer.push(t) }

        expect(output.length).to eq(4)
        expect(output).to_not include(*traces.last(2))

        # Last 2 traces will be dropped, without triggering stats.
        dropped_traces = traces.reject { |t| output.include?(t) }
        expected_traces = traces - dropped_traces
        expected_spans = expected_traces.inject(0) { |sum, t| sum + t.length }

        # Calling #pop produces metrics:
        # Metrics for accept events and no drop events
        # When the buffer is closed, drops don't count. (Should they?)
        expect(health_metrics).to have_received(:queue_accepted)
          .with(4)
        expect(health_metrics).to have_received(:queue_accepted_lengths)
          .with(expected_spans)
        expect(health_metrics).to have_received(:queue_dropped)
          .with(0)

        # Metrics for queue gauges.
        expect(health_metrics).to have_received(:queue_max_length)
          .with(max_size)
        expect(health_metrics).to have_received(:queue_spans)
          .with(expected_spans)
        expect(health_metrics).to have_received(:queue_length)
          .with(expected_traces.length)
      end
    end
  end

  describe '#pop' do
    subject(:pop) { buffer.pop }
    let(:traces) { get_test_traces(2) }

    before do
      traces.each { |t| buffer.push(t) }
    end

    it do
      expect(pop.length).to eq(traces.length)
      expect(pop).to include(*traces)
      expect(buffer.empty?).to be true

      expected_spans = traces.inject(0) { |sum, t| sum + t.length }

      # Calling #pop produces metrics:
      # Metrics for accept events and one drop event
      expect(health_metrics).to have_received(:queue_accepted)
        .with(traces.length)
      expect(health_metrics).to have_received(:queue_accepted_lengths)
        .with(expected_spans)

      expect(health_metrics).to have_received(:queue_dropped)
        .with(0)

      # Metrics for queue gauges.
      expect(health_metrics).to have_received(:queue_max_length)
        .with(max_size)
      expect(health_metrics).to have_received(:queue_spans)
        .with(expected_spans)
      expect(health_metrics).to have_received(:queue_length)
        .with(traces.length)
    end
  end
end
