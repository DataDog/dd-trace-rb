require "spec_helper"

require "timeout"
require "datadog/core/transport/http/adapters/native"

RSpec.describe Datadog::Core::Transport::HTTP::Adapters::Native::InFlight do
  subject(:in_flight) { described_class.new }

  def wait_until_sleeping(thread)
    Thread.pass until thread.status == "sleep"
  end

  # Runs a call that stays in flight until the returned queue receives something.
  def start_blocked_call
    inside = Queue.new
    release = Queue.new
    thread = Thread.new { in_flight.track { inside << true && release.pop } }
    inside.pop
    [thread, release]
  end

  describe "#track" do
    it "returns the value of the block" do
      expect(in_flight.track { 42 }).to eq(42)
    end

    it "does not swallow exceptions, and stops counting the call" do
      expect { in_flight.track { raise "boom" } }.to raise_error("boom")

      expect(Timeout.timeout(1) { in_flight.pause }).to be_nil
    end

    it "allows concurrent calls" do
      calls = Array.new(3) { start_blocked_call }

      calls.each { |_thread, release| release << true }
      calls.each { |thread, _release| thread.join }
    end
  end

  describe "#pause and #resume" do
    it "waits for the calls in flight" do
      call, release = start_blocked_call

      pausing = Thread.new { in_flight.pause }
      wait_until_sleeping(pausing)
      expect(pausing).to be_alive

      release << true
      [call, pausing].each(&:join)
    end

    it "makes new calls wait until resumed" do
      in_flight.pause

      ran = false
      call = Thread.new { in_flight.track { ran = true } }
      wait_until_sleeping(call)
      expect(ran).to be(false)

      in_flight.resume
      call.join
      expect(ran).to be(true)
    end

    it "keeps new calls waiting until every pause was resumed" do
      2.times { in_flight.pause }

      call = Thread.new { in_flight.track { :ran } }
      wait_until_sleeping(call)

      in_flight.resume
      # It wakes up, finds that it is still paused and waits again.
      Thread.pass until call.status == "sleep" || !call.status
      expect(call.status).to eq("sleep")

      in_flight.resume
      expect(call.value).to eq(:ran)
    end

    it "ignores a resume without a pause" do
      expect { in_flight.resume }.not_to raise_error
      expect(in_flight.track { :ran }).to eq(:ran)
    end
  end

  describe "#close" do
    it "returns true the first time and false afterwards" do
      expect(in_flight.close).to be(true)
      expect(in_flight.close).to be(false)
    end

    it "makes later calls raise" do
      in_flight.close

      expect { in_flight.track { :ran } }.to raise_error(described_class::Closed)
    end

    it "waits for the calls in flight" do
      call, release = start_blocked_call

      closing = Thread.new { in_flight.close }
      wait_until_sleeping(closing)
      expect(closing).to be_alive

      release << true
      [call, closing].each(&:join)
    end

    it "makes the calls waiting for a pause raise" do
      in_flight.pause
      call = Thread.new do
        Thread.current.report_on_exception = false
        in_flight.track { :ran }
      end
      wait_until_sleeping(call)

      in_flight.close

      expect { call.value }.to raise_error(described_class::Closed)
    end
  end
end
