require 'spec_helper'

require 'ddtrace'
require 'ddtrace/buffer'

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
    it do
      is_expected.to be_a_kind_of(described_class)

      expect(health_metrics).to have_received(:queue_max_length)
        .with(max_size)
    end
  end

  describe '#push' do
    let(:output) { buffer.pop }

    context 'given a trace' do
      subject(:push) { buffer.push(trace) }
      let(:trace) { get_test_traces(1).first }

      it 'sends health metrics' do
        push

        # Metrics for accept event
        expect(health_metrics).to have_received(:queue_accepted)
          .with(1)
        expect(health_metrics).to have_received(:queue_accepted_lengths)
          .with(trace.length)
        expect(health_metrics).to have_received_lazy_health_metric(
          :queue_accepted_size,
          measure_trace_size(trace)
        )

        # Metrics for queue gauges
        expect(health_metrics).to have_received(:queue_spans)
          .with(trace.length)
        expect(health_metrics).to have_received(:queue_length)
          .with(1)
        expect(health_metrics).to have_received_lazy_health_metric(
          :queue_size,
          measure_traces_size([trace])
        )
      end
    end

    context 'given no limit' do
      let(:traces) { get_test_traces(4) }
      let(:max_size) { 0 }

      it 'retains all items' do
        traces.each { |t| buffer.push(t) }
        expect(output.length).to eq(4)
      end
    end

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

        # Metrics for accept events and one drop event
        expect(health_metrics).to have_received(:queue_accepted)
          .with(1).exactly(3).times
        expect(health_metrics).to have_received(:queue_accepted_lengths)
          .with(kind_of(Numeric)).exactly(3).times

        expect(health_metrics).to have_received(:queue_accepted_size) { |&block|
          @i ||= 0
          expect(block.call).to eq(measure_trace_size(traces[@i]))
          @i += 1
        }.exactly(3).times

        expect(health_metrics).to have_received(:queue_dropped)
          .with(dropped_traces.length).once

        # Metrics for queue gauges; for each #push and once for the #pop
        expect(health_metrics).to have_received(:queue_length)
          .with(kind_of(Numeric)).exactly(5).times
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

        expect(health_metrics).to have_received(:queue_accepted).exactly(4).times
        # When the buffer is closed, drops don't count. (Should they?)
        expect(health_metrics).to_not have_received(:queue_dropped)
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
    let(:traces) { get_test_traces(2) }

    before do
      traces.each { |t| buffer.push(t) }
    end

    it do
      expect(pop.length).to eq(traces.length)
      expect(pop).to include(*traces)
      expect(buffer.empty?).to be true

      # Metrics for queue, once for each #push, once for the #pop.
      traces.length.times do |i|
        expect(health_metrics).to have_received(:queue_spans)
          .with(traces.first(i + 1).inject(0) { |sum, trace| sum + trace.length }).ordered
        expect(health_metrics).to have_received(:queue_length)
          .with(i + 1).ordered
      end

      expect(health_metrics).to have_received(:queue_spans)
        .with(0).ordered
      expect(health_metrics).to have_received(:queue_length)
        .with(0).ordered

      # Once for each #push, once for the #pop.
      expect(health_metrics).to have_received_lazy_health_metric(
        :queue_size,
        Datadog::Runtime::ObjectSpace.estimate_bytesize([])
      ).exactly(3).times
    end
  end
end
