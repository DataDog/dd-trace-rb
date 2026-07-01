require "datadog/di/spec_helper"

# Unit tests for the C-implemented re-entrancy guard primitives:
# Datadog::DI.in_probe?, .enter_probe, .leave_probe.
#
# Storage is the same fiber-local hashtable that backs Thread#[] / Thread#[]=,
# but accessed via rb_thread_local_aref / rb_thread_local_aset (no method
# dispatch). These tests exercise the basic semantics and verify that the
# guard is fiber-local — independent across threads and across fibers within
# a single thread.

RSpec.describe "Datadog::DI re-entrancy guard primitives" do
  # Always leave the guard cleared regardless of test outcome so that one
  # test's leftover state cannot affect the next.
  after { Datadog::DI.leave_probe }

  describe ".in_probe?" do
    context "with no enter_probe call on this fiber" do
      it "returns false" do
        expect(Datadog::DI.in_probe?).to be false
      end
    end

    context "after enter_probe" do
      it "returns true" do
        Datadog::DI.enter_probe
        expect(Datadog::DI.in_probe?).to be true
      end
    end

    context "after enter_probe followed by leave_probe" do
      it "returns false" do
        Datadog::DI.enter_probe
        Datadog::DI.leave_probe
        expect(Datadog::DI.in_probe?).to be false
      end
    end
  end

  describe "fiber locality" do
    it "does not leak guard state from parent fiber to a child fiber" do
      Datadog::DI.enter_probe

      observed = nil
      Fiber.new { observed = Datadog::DI.in_probe? }.resume

      expect(observed).to be false
      expect(Datadog::DI.in_probe?).to be true
    end

    it "does not leak guard state from a child fiber to the parent" do
      child_set = nil
      Fiber.new do
        Datadog::DI.enter_probe
        child_set = Datadog::DI.in_probe?
      end.resume

      expect(child_set).to be true
      expect(Datadog::DI.in_probe?).to be false
    end
  end

  describe "thread locality" do
    it "does not leak guard state across threads" do
      Datadog::DI.enter_probe

      observed = nil
      Thread.new { observed = Datadog::DI.in_probe? }.join

      expect(observed).to be false
      expect(Datadog::DI.in_probe?).to be true
    end
  end

  describe "shares storage with Thread.current[:datadog_di_in_probe]" do
    # The C primitives must read/write the same hashtable that Thread#[]
    # uses, so that a switch to or from the C path (or vice versa) sees a
    # consistent guard state. This pins the storage key contract.

    it "exposes the C write to Thread.current[]" do
      Datadog::DI.enter_probe
      expect(Thread.current[:datadog_di_in_probe]).to be true
    end

    it "observes a Thread.current[]= write via the C reader" do
      Thread.current[:datadog_di_in_probe] = true
      expect(Datadog::DI.in_probe?).to be true
    ensure
      Thread.current[:datadog_di_in_probe] = nil
    end
  end
end
