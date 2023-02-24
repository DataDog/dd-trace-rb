require 'spec_helper'

require 'benchmark'
require 'concurrent'

RSpec.shared_examples 'thread-safe buffer' do
  subject(:buffer) { described_class.new(max_size) }

  let(:max_size) { 0 }
  let(:items) { defined?(super) ? super() : Array.new(items_count) { Object.new } }
  let(:items_count) { 10 }

  describe '#push' do
    let(:output) { buffer.pop }
    let(:wait_for_threads) { threads.each { |t| raise 'Thread wait timeout' unless t.join(5000) } }
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

    subject(:push) { threads.each(&:join) }

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
        expect(output).to have_at_most(max_size).items
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
            Thread.pass
          end

          push
        end
      end
    end
  end

  describe '#concat' do
    let(:output) { buffer.pop }
    let(:wait_for_threads) { threads.each { |t| raise 'Thread wait timeout' unless t.join(5000) } }
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

    subject(:concat) { wait_for_threads }

    it 'does not have collisions' do
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
        expect(output).to have_at_most(max_size).items
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
            Thread.pass
          end

          concat
        end
      end
    end
  end

  describe '#pop' do
    subject(:pop) { buffer.pop }

    let(:items) { Array.new(2) { Object.new } }

    before do
      items.each { |i| buffer.push(i) }
    end

    it { is_expected.to eq(items) }
  end
end

# :nocov:
RSpec.shared_examples 'performance' do
  subject(:buffer) { described_class.new(max_size) }

  let(:max_size) { 0 }

  require 'benchmark'
  let(:n) { 10_000 }
  let(:test_item_count) { 20 }

  def get_test_items(n = 1)
    Array.new(n) { Object.new }
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
# :nocov:
