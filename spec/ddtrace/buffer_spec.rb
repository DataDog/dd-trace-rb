require 'spec_helper'

require 'ddtrace'
require 'ddtrace/buffer'

RSpec.describe Datadog::TraceBuffer do
  subject(:buffer) { described_class.new(max_size) }
  let(:max_size) { 0 }

  describe '#initialize' do
    it do
      is_expected.to be_a_kind_of(described_class)
    end
  end

  describe '#push' do
    subject(:push) { buffer.push(trace) }
    let(:trace) { get_test_traces(1).first }

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
    end
  end
end
