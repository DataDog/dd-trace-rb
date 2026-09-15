# frozen_string_literal: true

require "spec_helper"
require "datadog/core/remote/worker"

RSpec.describe Datadog::Core::Remote::Worker do
  let(:task) { proc { 1 + 1 } }
  let(:logger) { logger_allowing_debug }
  subject(:worker) { described_class.new(interval: 1, logger: logger, &task) }

  describe "#initialize" do
    it "raises ArgumentError when no block is provided" do
      expect do
        described_class.new(interval: 1)
      end.to raise_error(ArgumentError)
    end
  end

  describe "#start" do
    after { worker.stop }

    it "mark worker as started" do
      expect(worker).not_to be_started
      worker.start
      expect(worker).to be_started
    end

    it "acquire and release lock" do
      expect(worker.instance_variable_get(:@mutex)).to receive(:synchronize).at_least(:once)
      worker.start
    end

    context "execute block when started" do
      let(:result) { [] }
      let(:queue) { Queue.new }
      let(:task) do
        proc do
          value = 1
          result << value
          queue << value
        end
      end

      it "runs block" do
        worker.start
        # Wait for the work task to execute once
        queue.pop
        expect(result).to eq([1])
      end
    end

    it "names the worker thread" do
      worker.start

      expect(Thread.list.map(&:name)).to include(described_class.to_s)
    end

    # See https://github.com/puma/puma/blob/32e011ab9e029c757823efb068358ed255fb7ef4/lib/puma/cluster.rb#L353-L359
    it "marks the worker thread as fork-safe (to avoid fork-safety warnings in webservers)" do
      worker.start

      expect(worker.instance_variable_get(:@thr).thread_variable_get(:fork_safe)).to be true
    end

    it "does not restart the worker after being stopped once" do
      worker.start
      expect(worker.instance_variable_get(:@started)).to be true

      worker.stop

      worker.start
      expect(worker.instance_variable_get(:@started)).to be false
    end
  end

  describe "#stop" do
    it "mark worker as stopped" do
      expect(worker).not_to be_started
      worker.start
      expect(worker).to be_started
      worker.stop
      expect(worker).not_to be_started
    end

    it "acquire and release lock" do
      expect(worker.instance_variable_get(:@mutex)).to receive(:synchronize).at_least(:once)
      worker.stop
    end
  end

  describe "#after_fork" do
    %i[starting started].each do |state|
      it "restarts a worker inherited while #{state}" do
        worker.instance_variable_set(:"@#{state}", true)
        worker.instance_variable_set(:@thr, Thread.current)
        allow(worker).to receive(:start)

        worker.after_fork

        expect(worker).to have_received(:start).once
        expect(worker.instance_variable_get(:@starting)).to be(false)
        expect(worker.instance_variable_get(:@started)).to be(false)
        expect(worker.instance_variable_get(:@thr)).to be_nil
      end
    end

    it "does not start a worker that was not running before the fork" do
      expect(worker).not_to receive(:start)

      worker.after_fork
    end

    it "does not restart a stopped worker" do
      worker.stop
      expect(worker).not_to receive(:start)

      worker.after_fork
    end
  end
end
