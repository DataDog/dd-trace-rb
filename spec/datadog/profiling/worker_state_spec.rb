require "spec_helper"
require "datadog/profiling/worker_state"

RSpec.describe Datadog::Profiling::WorkerState do
  subject(:worker_state) { described_class.new }

  let(:failure) { RuntimeError.new("test failure") }

  describe "#wait" do
    it "returns :not_started when the worker doesn't start on time" do
      expect(worker_state.wait(0)).to be :not_started
    end

    it "returns :running once the worker runs" do
      worker_state.running!

      expect(worker_state.wait(0)).to be :running
    end

    it "returns the failure once the worker failed" do
      worker_state.failed!(failure)

      expect(worker_state.wait(0)).to be failure
    end

    [:running!, :failed!].each do |transition|
      it "wakes up a waiting thread on #{transition}" do
        waiter = Thread.new { worker_state.wait(60) }
        try_wait_until(backoff: 0.01) { waiter.status == "sleep" }

        (transition == :failed!) ? worker_state.failed!(failure) : worker_state.running!

        expect(waiter.join(10)&.value).to eq((transition == :failed!) ? failure : :running)
      ensure
        waiter&.kill
        waiter&.join
      end
    end
  end

  describe "#failure" do
    it "returns the failure" do
      worker_state.failed!(failure)

      expect(worker_state.failure).to be failure
    end
  end

  describe "#reset!" do
    it "forgets that the worker ran or failed" do
      worker_state.running!
      worker_state.failed!(failure)

      worker_state.reset!

      expect(worker_state.wait(0)).to be :not_started
      expect(worker_state.failure).to be nil
    end
  end
end
