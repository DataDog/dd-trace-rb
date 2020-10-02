require 'spec_helper'

require 'ddtrace'
require 'ddtrace/buffer'

require 'concurrent'

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
  end

  describe '#concat' do
    let(:output) { buffer.pop }

    context 'given no limit' do
      let(:items) { get_test_items(4) }
      let(:max_size) { 0 }

      it 'retains all items' do
        buffer.concat(items)
        expect(output.length).to eq(4)
      end
    end

    context 'given a max size' do
      let(:items) { get_test_items(max_size + 1) }
      let(:max_size) { 3 }

      it 'does not exceed it' do
        buffer.concat(items)

        expect(output.length).to eq(max_size)
        expect(output).to include(items.last)
      end
    end

    context 'when closed' do
      let(:max_size) { 0 }
      let(:items) { get_test_items(6) }

      let(:output) { buffer.pop }

      it 'retains items up to close' do
        buffer.concat(items[0..3])
        buffer.close
        buffer.concat(items[4..5])

        expect(output.length).to eq(4)
        expect(output).to_not include(*items.last(2))
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

  describe '#close' do
    subject(:close) { buffer.close }

    it do
      expect { close }
        .to change { buffer.closed? }
        .from(false)
        .to(true)
    end
  end

  describe '#closed?' do
    subject(:closed?) { buffer.closed? }

    context 'when the buffer has not been closed' do
      it { is_expected.to be false }
    end

    context 'when the buffer is closed' do
      before { buffer.close }
      it { is_expected.to be true }
    end
  end

  describe 'performance' do
    require 'benchmark'
    let(:n) { 10_000 }
    let(:test_item_count) { 20 }

    before { skip('Performance test does not run in CI.') }

    context 'no max_size' do
      it do
        Benchmark.bmbm do |x|
          x.report('No max #push') do
            n.times do
              buffer = described_class.new(max_size)
              items = get_test_items(test_item_count)

              items.each { |item| buffer.push(item) }
            end
          end

          x.report('No max #concat') do
            n.times do
              buffer = described_class.new(max_size)
              items = get_test_items(test_item_count)

              buffer.concat(items)
            end
          end
        end
      end
    end

    context 'max size' do
      let(:max_size) { 20 }

      context 'no overflow' do
        let(:test_item_count) { max_size }

        it do
          Benchmark.bmbm do |x|
            x.report('Max no overflow #push') do
              n.times do
                buffer = described_class.new(max_size)
                items = get_test_items(test_item_count)

                items.each { |item| buffer.push(item) }
              end
            end

            x.report('Max no overflow #concat') do
              n.times do
                buffer = described_class.new(max_size)
                items = get_test_items(test_item_count)

                buffer.concat(items)
              end
            end
          end
        end
      end

      context 'partial overflow' do
        let(:test_item_count) { max_size + super() }

        it do
          Benchmark.bmbm do |x|
            x.report('Max partial overflow #push') do
              n.times do
                buffer = described_class.new(max_size)
                items = get_test_items(test_item_count)

                items.each { |item| buffer.push(item) }
              end
            end

            x.report('Max partial overflow #concat') do
              n.times do
                buffer = described_class.new(max_size)
                items = get_test_items(test_item_count)

                buffer.concat(items)
              end
            end
          end
        end
      end

      context 'total overflow' do
        it do
          Benchmark.bmbm do |x|
            x.report('Max total overflow #push') do
              n.times do
                buffer = described_class.new(max_size)
                buffer.instance_variable_set(:@items, get_test_items(max_size))
                items = get_test_items(test_item_count)

                items.each { |item| buffer.push(item) }
              end
            end

            x.report('Max total overflow #concat') do
              n.times do
                buffer = described_class.new(max_size)
                buffer.instance_variable_set(:@items, get_test_items(max_size))
                items = get_test_items(test_item_count)

                buffer.concat(items)
              end
            end
          end
        end
      end
    end
  end
end

RSpec.describe Datadog::TraceBuffer do
  subject(:buffer_class) { described_class }

  context 'with CRuby' do
    before { skip unless PlatformHelpers.mri? }
    it { is_expected.to eq Datadog::CRubyTraceBuffer }
  end

  context 'with JRuby' do
    before { skip unless PlatformHelpers.jruby? }
    it { is_expected.to eq Datadog::ThreadSafeTraceBuffer }
  end
end

RSpec.shared_examples 'thread-safe buffer' do
  subject(:buffer) { described_class.new(max_size) }

  let(:max_size) { 0 }
  let(:max_size_leniency) { defined?(super) ? super() : 1 } # Multiplier to allowed max_size

  let(:items) { defined?(super) ? super() : Array.new(items_count) { double('item') } }
  let(:items_count) { 10 }

  describe '#push' do
    let(:output) { buffer.pop }

    subject(:push) { threads.each(&:join) }

    let(:max_size) { 500 }
    let(:thread_count) { 100 }
    let(:threads) do
      buffer
      items

      Array.new(thread_count) do |_i|
        Thread.new do
          sleep(rand / 1000.0)
          buffer.push(items)
        end
      end
    end

    let(:output) { buffer.pop }

    it 'does not have collisions' do
      push
      expect(output).to_not be nil
      expect(output).to match_array(Array.new(thread_count) { items })
    end

    context 'with items exceeding maximum size' do
      let(:max_size) { 100 }
      let(:thread_count) { 100 }
      let(:barrier) { Concurrent::CyclicBarrier.new(thread_count) }
      let(:threads) do
        buffer
        barrier
        items

        Array.new(thread_count) do |_i|
          Thread.new do
            barrier.wait
            1000.times { buffer.push(items) }
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

  describe '#concat' do
    let(:output) { buffer.pop }

    subject(:concat) { threads.each { |t| t.join(5000) } }

    let(:bulk_items) { Array.new(10, items) }

    let(:max_size) { 5000 }
    let(:thread_count) { 100 }
    let(:threads) do
      buffer
      bulk_items

      Array.new(thread_count) do |_i|
        Thread.new do
          sleep(rand / 1000.0)
          buffer.concat(bulk_items)
        end
      end
    end

    let(:output) { buffer.pop }

    xit 'does not have collisions' do
      concat
      expect(output).to_not be nil
      expect(output).to match_array(thread_count.times.flat_map { bulk_items })
    end

    context 'with items exceeding maximum size' do
      let(:max_size) { 100 }
      let(:thread_count) { 100 }
      let(:items_count) { 10 }
      let(:barrier) { Concurrent::CyclicBarrier.new(thread_count) }
      let(:threads) do
        buffer
        barrier
        items

        Array.new(thread_count) do |_i|
          Thread.new do
            barrier.wait
            500.times { buffer.concat(items) }
          end
        end
      end

      it 'does not exceed expected maximum size' do
        concat
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

          concat
        end
      end
    end
  end

  describe '#pop' do
    subject(:pop) { buffer.pop }
    let(:traces) { get_test_traces(2) }

    before do
      traces.each { |t| buffer.push(t) }
    end
  end
end

RSpec.shared_examples 'trace buffer' do
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
    it { is_expected.to be_a_kind_of(described_class) }
  end

  describe '#push' do
    subject(:push) { items.each { |t| buffer.push(t) } }

    let(:items_count) { max_size + 1 }
    let(:pop) { buffer.pop }

    context 'given a max size' do
      let(:max_size) { 3 }

      it 'records health metrics' do
        push

        accepted_spans = items.inject(0) { |sum, t| sum + t.length }

        # A trace will be dropped at random, except the trace
        # that triggered the overflow.
        dropped_traces = items.reject { |t| pop.include?(t) }

        expected_traces = items - dropped_traces
        net_spans = expected_traces.inject(0) { |sum, t| sum + t.length }

        # Calling #pop produces metrics:
        # Accept events for every #push, and one drop event for overflow
        expect(health_metrics).to have_received(:queue_accepted)
          .with(items.length)
        expect(health_metrics).to have_received(:queue_accepted_lengths)
          .with(accepted_spans)

        expect(health_metrics).to have_received(:queue_dropped)
          .with(dropped_traces.length)

        # Metrics for queue gauges.
        expect(health_metrics).to have_received(:queue_max_length)
          .with(max_size)
        expect(health_metrics).to have_received(:queue_spans)
          .with(net_spans)
        expect(health_metrics).to have_received(:queue_length)
          .with(max_size)
      end
    end
  end

  describe '#concat' do
    let(:output) { buffer.pop }

    context 'given no limit' do
      let(:items) { get_test_traces(4) }
      let(:max_size) { 0 }

      it 'retains all items' do
        buffer.concat(items)
        expect(output.length).to eq(4)
      end
    end

    context 'given a max size' do
      let(:items) { get_test_traces(max_size + 1) }
      let(:max_size) { 3 }

      it 'does not exceed it' do
        buffer.concat(items)

        expect(output.length).to eq(max_size)
        expect(output).to include(items.last)
      end
    end
  end

  describe '#pop' do
    subject(:pop) { buffer.pop }
    let(:traces) { get_test_traces(2) }

    before { traces.each { |t| buffer.push(t) } }

    it 'records health metrics' do
      pop

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

RSpec.shared_examples 'performance' do
  subject(:buffer) { described_class.new(max_size) }
  let(:max_size) { 0 }

  require 'benchmark'
  let(:n) { 10_000 }
  let(:test_item_count) { 20 }

  def get_test_items(n = 1)
    Array.new(n) { double('item') }
  end

  before { skip('Performance test does not run in CI.') }

  context 'no max_size' do
    it do
      Benchmark.bmbm do |x|
        x.report('No max #push') do
          n.times do
            buffer = described_class.new(max_size)
            items = get_test_items(test_item_count)

            items.each { |item| buffer.push(item) }
          end
        end

        x.report('No max #concat') do
          n.times do
            buffer = described_class.new(max_size)
            items = get_test_items(test_item_count)

            buffer.concat(items)
          end
        end
      end
    end
  end

  context 'max size' do
    let(:max_size) { 20 }

    context 'no overflow' do
      let(:test_item_count) { max_size }

      it do
        Benchmark.bmbm do |x|
          x.report('Max no overflow #push') do
            n.times do
              buffer = described_class.new(max_size)
              items = get_test_items(test_item_count)

              items.each { |item| buffer.push(item) }
            end
          end

          x.report('Max no overflow #concat') do
            n.times do
              buffer = described_class.new(max_size)
              items = get_test_items(test_item_count)

              buffer.concat(items)
            end
          end
        end
      end
    end

    context 'partial overflow' do
      let(:test_item_count) { max_size + super() }

      it do
        Benchmark.bmbm do |x|
          x.report('Max partial overflow #push') do
            n.times do
              buffer = described_class.new(max_size)
              items = get_test_items(test_item_count)

              items.each { |item| buffer.push(item) }
            end
          end

          x.report('Max partial overflow #concat') do
            n.times do
              buffer = described_class.new(max_size)
              items = get_test_items(test_item_count)

              buffer.concat(items)
            end
          end
        end
      end
    end

    context 'total overflow' do
      it do
        Benchmark.bmbm do |x|
          x.report('Max total overflow #push') do
            n.times do
              buffer = described_class.new(max_size)
              buffer.instance_variable_set(:@items, get_test_items(max_size))
              items = get_test_items(test_item_count)

              items.each { |item| buffer.push(item) }
            end
          end

          x.report('Max total overflow #concat') do
            n.times do
              buffer = described_class.new(max_size)
              buffer.instance_variable_set(:@items, get_test_items(max_size))
              items = get_test_items(test_item_count)

              buffer.concat(items)
            end
          end
        end
      end
    end
  end
end

RSpec.describe Datadog::ThreadSafeBuffer do
  it_behaves_like 'thread-safe buffer'
  it_behaves_like 'performance'
end

RSpec.describe Datadog::CRubyBuffer do
  before { skip unless PlatformHelpers.mri? }

  it_behaves_like 'thread-safe buffer' do
    let(:max_size_leniency) { 1.04 } # 4%
  end
  it_behaves_like 'performance'
end

RSpec.describe Datadog::ThreadSafeTraceBuffer do
  it_behaves_like 'trace buffer'
  it_behaves_like 'thread-safe buffer'
  it_behaves_like 'performance'

  let(:items) { get_test_traces(items_count) }
end

RSpec.describe Datadog::CRubyTraceBuffer do
  before { skip unless PlatformHelpers.mri? }

  it_behaves_like 'trace buffer'
  it_behaves_like 'thread-safe buffer' do
    let(:max_size_leniency) { 1.04 } # 4%
  end
  it_behaves_like 'performance'

  let(:items) { get_test_traces(items_count) }
end
