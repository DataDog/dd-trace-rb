# frozen_string_literal: true

require "spec_helper"
require "datadog/open_feature/transport"

RSpec.describe Datadog::OpenFeature::Exposures::Worker do
  let(:debug_messages) { [] }

  before do
    allow(logger).to receive(:debug) do |message, &block|
      debug_messages << (block ? block.call : message) if logger.debug?
    end
  end

  after do
    worker.stop(true, 0.1)
    worker.join
  end

  subject(:worker) do
    described_class.new(
      settings: settings,
      transport: transport,
      telemetry: telemetry,
      logger: logger,
      flush_interval_seconds: 0.1,
      buffer_limit: 2
    )
  end

  let(:settings) { Datadog::Core::Configuration::Settings.new }
  let(:transport) { instance_double(Datadog::OpenFeature::Transport::HTTP) }
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }
  let(:response) { instance_double(Datadog::Core::Transport::HTTP::Adapters::Net::Response, ok?: true) }
  let(:logger) { instance_double(Datadog::Core::Logger, debug: nil, debug?: true) }
  let(:event) do
    {
      timestamp: 1_735_689_600_000,
      allocation: {key: "control"},
      flag: {key: "demo-flag"},
      variant: {key: "v1"},
      subject: {id: "user-1", attributes: {"plan" => "pro"}},
    }
  end

  describe "#start" do
    context "when worker is disabled" do
      it "does nothing" do
        allow(worker).to receive(:enabled?).and_return(false)

        worker.start

        expect(worker).not_to be_running
        expect(worker).not_to be_started
      end
    end
  end

  describe "#enqueue" do
    it "rejects a closed buffer without claiming the exposure was queued" do
      worker.buffer.close
      expect(worker.enqueue(event)).to be(false)
      expect(worker.buffer).to be_empty

      expect(debug_messages).to include("Feature Flags: exposure not queued: buffer closed")
    end

    it "reports older queued exposures evicted by a full buffer" do
      allow(worker).to receive(:start)
      allow(transport).to receive(:send_exposures).and_return(response)
      3.times { expect(worker.enqueue(event)).to be(true) }
      worker.send(:send_events, *worker.dequeue)

      expect(debug_messages).to include("Feature Flags: dropped 1 older queued exposure event(s) because the exposure buffer was full")
      expect(debug_messages).to include("Feature Flags: flushing 2 exposure event(s) to Datadog")
    end

    context "when worker is not started" do
      let(:event_2) do
        {
          timestamp: 1_735_689_600_000,
          allocation: {key: "control-2"},
          flag: {key: "demo-flag2"},
          variant: {key: "v2"},
          subject: {id: "user-2", attributes: {"plan" => "pro"}},
        }
      end
      let(:event_3) do
        {
          timestamp: 1_735_689_600_000,
          allocation: {key: "control-3"},
          flag: {key: "demo-flag3"},
          variant: {key: "v3"},
          subject: {id: "user-3", attributes: {"plan" => "pro"}},
        }
      end

      it "starts on demand and processes buffer" do
        batches_sent = 0
        allow(transport).to receive(:send_exposures) do |payload|
          batches_sent += 1
          response
        end

        worker.enqueue(event)
        worker.enqueue(event_2)
        worker.enqueue(event_3)

        try_wait_until { worker.running? }
        try_wait_until { batches_sent.positive? }

        expect(batches_sent).to eq(1)
      end
    end

    context "when transport response is ok" do
      before { allow(transport).to receive(:send_exposures).and_return(response) }

      it "logs that the transport accepted the events" do
        worker.enqueue(event)
        try_wait_until { worker.running? }

        worker.flush

        expect(debug_messages).to include("Feature Flags: sent 1 exposure event(s) to Datadog")
      end
    end

    context "when transport response does not have expected interface" do
      before { allow(transport).to receive(:send_exposures).and_return(response) }

      let(:response) { nil }

      it "logs debug message" do
        worker.enqueue(event)
        try_wait_until { worker.running? }

        worker.flush

        expect(debug_messages).to include(/exposure upload response was not OK; dropping 1 exposure event\(s\) without retry/)
      end
    end

    context "when transport response is not ok" do
      before { allow(transport).to receive(:send_exposures).and_return(response) }

      let(:response) { instance_double(Datadog::Core::Transport::HTTP::Adapters::Net::Response, ok?: false) }

      it "logs debug message" do
        worker.enqueue(event)
        try_wait_until { worker.running? }

        worker.flush

        expect(debug_messages).to include(/exposure upload response was not OK; dropping 1 exposure event\(s\) without retry/)
      end
    end

    context "when transport raises an error" do
      before { allow(transport).to receive(:send_exposures).and_raise(error) }

      let(:error) { StandardError.new("Ooops") }

      it "logs debug message and swallows the error" do
        expect(telemetry).to receive(:report).with(error, description: /Failed to flush resolution details events/)

        worker.enqueue(event)
        try_wait_until { worker.running? }

        expect { worker.perform }.not_to raise_error

        worker.flush

        expect(debug_messages).to include(/failed to flush exposure events; dropping 1 exposure event\(s\) without retry: StandardError: Ooops/)
      end
    end
  end

  it "discards inherited pending exposures and delivers child events after fork" do
    sent = []
    allow(transport).to receive(:send_exposures) { |payload|
      sent << payload
      response
    }
    worker.send(:loop_base_interval=, 30)
    worker.enqueue(event)
    try_wait_until { sent.size == 1 }
    worker.buffer.push(event.merge(subject: {id: "parent-pending"}))
    expect_in_fork do
      sent.clear
      worker.enqueue(event.merge(subject: {id: "child"}))
      worker.graceful_shutdown
      expect(sent.flat_map { |payload| payload[:exposures].map { |exposure| exposure[:subject][:id] } }).to eq(["child"])
    end
  end

  describe "#graceful_shutdown" do
    it "bounds shutdown even when a delivery cannot finish" do
      stub_const("Datadog::OpenFeature::Exposures::Worker::GRACEFUL_SHUTDOWN_TIMEOUT_SECONDS", 0.1)
      entered = Queue.new
      release = Queue.new
      allow(transport).to receive(:send_exposures) do
        entered << true
        release.pop
      end
      worker.enqueue(event)
      Timeout.timeout(1) { entered.pop }
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      worker.graceful_shutdown
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 1
      expect(worker).not_to be_running
      expect(worker.enqueue(event)).to be(false)
    ensure
      release << response
    end

    it "reports an in-flight upload before stopping and only then reports completion" do
      entered = Queue.new
      release = Queue.new
      allow(transport).to receive(:send_exposures) do
        entered << true
        release.pop
      end
      worker.enqueue(event)
      Timeout.timeout(1) { entered.pop }
      allow(worker).to receive(:stop).and_wrap_original { |method, force, _timeout| method.call(force, 0) }
      worker.graceful_shutdown
      expect(worker).not_to be_running
      expect(debug_messages).to include("Feature Flags: exposure worker stopping; queued=0, upload_in_progress=true, wait_budget=3s")
      expect(debug_messages.last(2)).to eq([
        "Feature Flags: exposure shutdown wait finished; queued=0, upload_in_progress=false, wait_budget=3s; no queued exposure events remain",
        "Feature Flags: exposure worker stopped",
      ])
    ensure
      release << true
    end

    it "can report the in-flight upload outcome while stop waits" do
      entered = Queue.new
      release = Queue.new
      allow(transport).to receive(:send_exposures) do
        entered << true
        release.pop
      end
      worker.enqueue(event)
      Timeout.timeout(1) { entered.pop }
      allow(worker).to receive(:join).and_wrap_original do |method, *args|
        release << response
        method.call(*args)
      end
      worker.graceful_shutdown
      expect(debug_messages.count("Feature Flags: sent 1 exposure event(s) to Datadog")).to eq(1)
      expect(worker.buffer.length).to eq(0)
      expect(debug_messages).to include("Feature Flags: exposure worker stopped")
      expect(worker).not_to be_running
    ensure
      release << response
    end

    context "when buffer contains events" do
      before do
        stub_const("Datadog::OpenFeature::Exposures::Worker::GRACEFUL_SHUTDOWN_TIMEOUT_SECONDS", 0.2)
      end

      let(:event_2) do
        {
          timestamp: 1_735_689_600_000,
          allocation: {key: "control-2"},
          flag: {key: "demo-flag2"},
          variant: {key: "v2"},
          subject: {id: "user-2", attributes: {"plan" => "pro"}},
        }
      end

      it "flushes remaining events before stopping" do
        batches_sent = 0
        allow(transport).to receive(:send_exposures) do |payload|
          batches_sent += 1
          response
        end

        worker.enqueue(event)
        try_wait_until { worker.running? }
        try_wait_until { batches_sent.positive? }

        worker.enqueue(event_2)
        worker.graceful_shutdown
        try_wait_until { !worker.running? }

        expect(batches_sent).to eq(2)
      end

      it "logs that no queued events remain" do
        messages = Queue.new
        allow(logger).to receive(:debug) { |message, &block| messages << (block ? block.call : message) }
        allow(transport).to receive(:send_exposures).and_return(response)

        worker.enqueue(event)
        worker.graceful_shutdown
        expect(worker).not_to be_running
        expect(Array.new(messages.size) { messages.pop }).to include(
          "Feature Flags: flushing 1 exposure event(s) to Datadog",
          "Feature Flags: exposure shutdown wait finished; queued=0, upload_in_progress=false, wait_budget=0.2s; no queued exposure events remain",
          "Feature Flags: exposure worker stopped"
        )
      end

      it "logs queued events that were not sent before the deadline" do
        messages = Queue.new
        allow(logger).to receive(:debug) { |message, &block| messages << (block ? block.call : message) }
        allow(worker).to receive(:start)

        worker.enqueue(event)
        worker.enqueue(event_2)
        worker.graceful_shutdown

        expect(Array.new(messages.size) { messages.pop }).to include(
          "Feature Flags: exposure shutdown wait finished; queued=2, upload_in_progress=false, wait_budget=0.2s; 2 queued exposure event(s) will not be sent",
        )
      end

      it "logs evicted events that were never flushed" do
        messages = Queue.new
        allow(logger).to receive(:debug) { |message, &block| messages << (block ? block.call : message) }
        allow(worker).to receive(:start)

        3.times { worker.enqueue(event) }
        worker.graceful_shutdown

        expect(Array.new(messages.size) { messages.pop }).to include(
          "Feature Flags: exposure shutdown wait finished; queued=2, upload_in_progress=false, wait_budget=0.2s; " \
            "2 queued exposure event(s) will not be sent; 1 exposure event(s) evicted from the full buffer were not sent",
        )
      end
    end
  end
end
