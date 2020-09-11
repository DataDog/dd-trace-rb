require 'spec_helper'

require 'ddtrace'
require 'ddtrace/buffer'

require 'concurrent'

RSpec.describe Datadog::TraceBuffer do
  subject(:buffer_class) { described_class }

  context 'with CRuby' do
    before { skip unless PlatformHelpers.mri? }
    it { is_expected.to be <= Datadog::CRubyTraceBuffer }
  end

  context 'with JRuby' do
    before { skip unless PlatformHelpers.jruby? }
    it { is_expected.to be <= Datadog::ThreadSafeBuffer }
  end
end

RSpec.shared_examples 'trace buffer' do
  include_context 'health metrics'

  subject(:buffer) { described_class.new(max_size) }
  let(:max_size) { 0 }
  let(:max_size_leniency) { defined?(super) ? super() : 1 } # Multiplier to allowed max_size

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
    it { is_expected.to be_a_kind_of(described_class) }
  end

  describe '#push' do
    let(:output) { buffer.pop }

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

      context 'with items exceeding maximum size' do
        let(:max_size) { 100 }
        let(:thread_count) { 1000 }
        let(:barrier) { Concurrent::CyclicBarrier.new(thread_count) }
        let(:threads) do
          buffer
          barrier

          Array.new(thread_count) do |i|
            Thread.new do
              barrier.wait
              1000.times { buffer.push([i]) }
            end
          end
        end

        it 'does not exceed expected maximum size' do
          push
          expect(output).to have_at_most(max_size * max_size_leniency).items
        end

        context 'with #pop operations' do
          let(:barrier) { Concurrent::CyclicBarrier.new(thread_count + 1) }

          before do
            allow(Datadog).to receive(:logger).and_return(double)
          end

          it 'executes without error' do
            threads

            barrier.wait
            1000.times do
              buffer.pop

              # Yield control to threads to increase contention.
              # Otherwise we might run #pop a few times in succession,
              # which doesn't help us stress test this case.
              sleep 0
            end

            threads.each(&:kill)

            push
          end
        end
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

RSpec.describe Datadog::ThreadSafeBuffer do
  it_behaves_like 'trace buffer'
end

RSpec.describe Datadog::CRubyTraceBuffer do
  before { skip unless PlatformHelpers.mri? }

  it_behaves_like 'trace buffer' do
    let(:max_size_leniency) { 1.04 } # 4%
  end
end
