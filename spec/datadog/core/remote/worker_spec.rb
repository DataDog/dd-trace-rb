# frozen_string_literal: true

require 'spec_helper'
require 'datadog/core/remote/worker'

RSpec.describe Datadog::Core::Remote::Worker do
  describe '#initialize' do
    it 'raises ArgumentError when no block is provided' do
      expect do
        described_class.new(interval: 1)
      end.to raise_error(ArgumentError)
    end
  end

  subject(:worker) do
    described_class.new(interval: 1) do
      1 + 1
    end
  end

  describe '#start' do
    it 'mark worker as started' do
      expect(worker).not_to be_started
      worker.start
      expect(worker).to be_started
      worker.stop
    end

    it 'acquire and release lock' do
      expect(worker).to receive(:acquire_lock)
      expect(worker).to receive(:release_lock)
      worker.start
    end

    it 'execute block when started' do
      result = []
      queue = Queue.new
      queue_worker = described_class.new(interval: 1) do
        result << queue.pop
      end
      queue_worker.start
      # Unblock worker thread
      queue << 1
      expect(result).to eq([1])
      queue_worker.stop
    end
  end

  describe '#stop' do
    it 'mark worker as stopped' do
      expect(worker).not_to be_started
      worker.start
      expect(worker).to be_started
      worker.stop
      expect(worker).not_to be_started
    end

    it 'acquire and release lock' do
      expect(worker).to receive(:acquire_lock)
      expect(worker).to receive(:release_lock)
      worker.stop
    end
  end
end
