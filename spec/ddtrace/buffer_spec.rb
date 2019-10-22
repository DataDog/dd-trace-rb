require 'spec_helper'

require 'ddtrace'
require 'ddtrace/buffer'

RSpec.describe Datadog::TraceBuffer do
  subject(:buffer) { described_class.new(max_size) }
  let(:max_size) { 0 }

  before do
    allow(Datadog::Debug::Health.metrics).to receive(:queue_max_length)
    allow(Datadog::Debug::Health.metrics).to receive(:queue_accepted)
    allow(Datadog::Debug::Health.metrics).to receive(:queue_accepted_lengths)
    allow(Datadog::Debug::Health.metrics).to receive(:queue_accepted_size)
    allow(Datadog::Debug::Health.metrics).to receive(:queue_dropped)
    allow(Datadog::Debug::Health.metrics).to receive(:queue_spans)
    allow(Datadog::Debug::Health.metrics).to receive(:queue_length)
    allow(Datadog::Debug::Health.metrics).to receive(:queue_size)
  end

  describe '#initialize' do
    it do
      is_expected.to be_a_kind_of(described_class)

      expect(Datadog::Debug::Health.metrics).to have_received(:queue_max_length)
        .with(max_size)
    end
  end

  describe '#push' do
    subject(:push) { buffer.push(trace) }
    let(:trace) { get_test_traces(1).first }

    it 'sends health metrics' do
      push

      # Metrics for accept event
      expect(Datadog::Debug::Health.metrics).to have_received(:queue_accepted)
        .with(1)
      expect(Datadog::Debug::Health.metrics).to have_received(:queue_accepted_lengths)
        .with(trace.length)
      expect(Datadog::Debug::Health.metrics).to have_received(:queue_accepted_size)
        .with(ObjectSpace.memsize_of(trace))

      # Metrics for queue gauges
      expect(Datadog::Debug::Health.metrics).to have_received(:queue_spans)
        .with(trace.length)
      expect(Datadog::Debug::Health.metrics).to have_received(:queue_length)
        .with(1)
      expect(Datadog::Debug::Health.metrics).to have_received(:queue_size)
        .with(ObjectSpace.memsize_of([trace]))
    end

    context 'given no limit' do
      subject(:push) do
        buffer.push([1])
        buffer.push([2])
        buffer.push([3])
        buffer.push([4])
      end

      let(:max_size) { 0 }
      let(:output) { buffer.pop }

      it 'retains all items' do
        push
        expect(output.length).to eq(4)
      end
    end

    context 'given a max size' do
      subject(:push) do
        buffer.push([1])
        buffer.push([2])
        buffer.push([3])
        buffer.push([4])
      end

      let(:max_size) { 3 }
      let(:output) { buffer.pop }

      it 'does not exceed it' do
        push
        expect(output.length).to eq(3)
        expect(output).to include([4])

        # Metrics for accept events and one drop event
        expect(Datadog::Debug::Health.metrics).to have_received(:queue_accepted)
          .with(1).exactly(3).times
        expect(Datadog::Debug::Health.metrics).to have_received(:queue_accepted_lengths)
          .with(1).exactly(3).times
        expect(Datadog::Debug::Health.metrics).to have_received(:queue_accepted_size)
          .with(ObjectSpace.memsize_of([1])).exactly(3).times

        expect(Datadog::Debug::Health.metrics).to have_received(:queue_dropped)
          .with(1).once

        # Metrics for queue gauges; once for 3rd push, once for 4th push.
        expect(Datadog::Debug::Health.metrics).to have_received(:queue_length)
          .with(3).twice
      end
    end

    context 'when closed' do
      subject(:push) do
        buffer.push([1])
        buffer.push([2])
        buffer.push([3])
        buffer.push([4])
        buffer.close
        buffer.push([5])
        buffer.push([6])
      end

      let(:output) { buffer.pop }

      it 'retains items up to close' do
        push
        expect(output.length).to eq(4)
        expect(output).to_not include([5], [6])
        expect(Datadog::Debug::Health.metrics).to have_received(:queue_accepted).exactly(4).times
        # When the buffer is closed, drops don't count. (Should they?)
        expect(Datadog::Debug::Health.metrics).to_not have_received(:queue_dropped)
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

    context 'given no traces' do
      it { is_expected.to eq(0) }
    end

    context 'given a trace' do
      before { buffer.push([1]) }
      it { is_expected.to eq(1) }
    end
  end

  describe '#empty?' do
    subject(:empty?) { buffer.empty? }

    context 'given no traces' do
      it { is_expected.to be true }
    end

    context 'given a trace' do
      before { buffer.push([1]) }
      it { is_expected.to be false }
    end
  end

  describe '#pop' do
    subject(:pop) { buffer.pop }

    let(:input_traces) { get_test_traces(2) }

    before do
      buffer.push(input_traces[0])
      buffer.push(input_traces[1])
    end

    it do
      expect(pop.length).to eq(2)
      expect(pop).to include(*input_traces)
      expect(buffer.empty?).to be true

      # Metrics for queue gauges
      expect(Datadog::Debug::Health.metrics).to have_received(:queue_spans)
        .with(0)
      expect(Datadog::Debug::Health.metrics).to have_received(:queue_length)
        .with(0)
      # Twice for the two pushes, once for the pop.
      expect(Datadog::Debug::Health.metrics).to have_received(:queue_size)
        .with(ObjectSpace.memsize_of([])).exactly(3).times
    end
  end
end
