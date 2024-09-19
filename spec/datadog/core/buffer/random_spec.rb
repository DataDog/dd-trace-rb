require 'spec_helper'

require 'benchmark'
require 'datadog/core/buffer/random'

RSpec.describe Datadog::Core::Buffer::Random do
  subject(:buffer) { described_class.new(max_size) }

  let(:max_size) { 0 }

  def get_test_items(n = 1)
    Array.new(n) { Object.new }
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

  # :nocov:
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
  # :nocov:
end
