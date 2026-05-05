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

  describe ".array_empty?" do
    # C-level emptiness check that bypasses Array#empty? method dispatch.
    # Used by the method probe wrapper to test args shape without giving
    # user-installed probes on Array#empty? a chance to recurse.

    it "returns true for an empty array" do
      expect(Datadog::DI.array_empty?([])).to be true
    end

    it "returns false for a non-empty array" do
      expect(Datadog::DI.array_empty?([1])).to be false
      expect(Datadog::DI.array_empty?([1, 2, 3])).to be false
      expect(Datadog::DI.array_empty?([nil])).to be false
    end

    it "does not dispatch Array#empty?" do
      # Override Array#empty? on a subclass and confirm the C primitive
      # does not call the override. This is the contract that protects
      # against re-entrancy when a user probe instruments Array#empty?.
      array_class = Class.new(Array) do
        def empty?
          raise "Array#empty? was called via method dispatch"
        end
      end
      arr = array_class.new
      expect { Datadog::DI.array_empty?(arr) }.not_to raise_error
      expect(Datadog::DI.array_empty?(arr)).to be true
    end

    it "raises TypeError when the argument is not an Array" do
      # RARRAY_LEN reads struct fields directly and would return garbage
      # for any non-Array type. Check_Type guards against passing the
      # wrong type by raising before the read.
      expect { Datadog::DI.array_empty?({}) }.to raise_error(TypeError)
      expect { Datadog::DI.array_empty?("string") }.to raise_error(TypeError)
      expect { Datadog::DI.array_empty?(nil) }.to raise_error(TypeError)
      expect { Datadog::DI.array_empty?(42) }.to raise_error(TypeError)
    end
  end

  describe ".hash_empty?" do
    # C-level emptiness check that bypasses Hash#empty? method dispatch.

    it "returns true for an empty hash" do
      expect(Datadog::DI.hash_empty?({})).to be true
    end

    it "returns false for a non-empty hash" do
      expect(Datadog::DI.hash_empty?({a: 1})).to be false
      expect(Datadog::DI.hash_empty?({a: nil})).to be false
    end

    it "does not dispatch Hash#empty?" do
      hash_class = Class.new(Hash) do
        def empty?
          raise "Hash#empty? was called via method dispatch"
        end
      end
      h = hash_class.new
      expect { Datadog::DI.hash_empty?(h) }.not_to raise_error
      expect(Datadog::DI.hash_empty?(h)).to be true
    end

    it "raises TypeError when the argument is not a Hash" do
      # RHASH_SIZE reads struct fields directly and would return garbage
      # for any non-Hash type. Check_Type guards against passing the
      # wrong type by raising before the read.
      expect { Datadog::DI.hash_empty?([]) }.to raise_error(TypeError)
      expect { Datadog::DI.hash_empty?("string") }.to raise_error(TypeError)
      expect { Datadog::DI.hash_empty?(nil) }.to raise_error(TypeError)
      expect { Datadog::DI.hash_empty?(42) }.to raise_error(TypeError)
    end
  end

  describe ".invoke_proc" do
    # C-level Proc invocation that bypasses Proc#call method dispatch.
    # Used by the method probe wrapper to invoke the do_super lambda (and
    # other internal lambdas) without giving user-installed probes on
    # Proc#call a chance to recurse.

    it "invokes a lambda with positional arguments" do
      sum = ->(a, b, c) { a + b + c }
      expect(Datadog::DI.invoke_proc(sum, 1, 2, 3)).to eq(6)
    end

    it "invokes a 0-arg lambda" do
      get_42 = -> { 42 }
      expect(Datadog::DI.invoke_proc(get_42)).to eq(42)
    end

    it "invokes a non-lambda Proc" do
      doubler = proc { |x| x * 2 }
      expect(Datadog::DI.invoke_proc(doubler, 21)).to eq(42)
    end

    it "propagates the proc's return value" do
      string_proc = ->(s) { s.upcase }
      expect(Datadog::DI.invoke_proc(string_proc, "hi")).to eq("HI")
    end

    it "propagates exceptions raised inside the proc" do
      raiser = -> { raise ArgumentError, "from proc" }
      expect { Datadog::DI.invoke_proc(raiser) }.to raise_error(ArgumentError, "from proc")
    end

    it "does not dispatch Proc#call" do
      # Override Proc#call on a subclass and confirm the C primitive does
      # not call the override. This is the contract that protects against
      # re-entrancy when a user probe instruments Proc#call.
      proc_class = Class.new(Proc) do
        def call(*)
          raise "Proc#call was called via method dispatch"
        end
      end
      p = proc_class.new { |x| x * 3 }
      expect { Datadog::DI.invoke_proc(p, 7) }.not_to raise_error
      expect(Datadog::DI.invoke_proc(p, 7)).to eq(21)
    end

    it "raises TypeError when the first argument is not a Proc" do
      expect { Datadog::DI.invoke_proc("not a proc") }.to raise_error(TypeError)
      expect { Datadog::DI.invoke_proc(nil) }.to raise_error(TypeError)
      expect { Datadog::DI.invoke_proc(42) }.to raise_error(TypeError)
      expect { Datadog::DI.invoke_proc([]) }.to raise_error(TypeError)
    end

    it "raises ArgumentError when no arguments are given" do
      expect { Datadog::DI.invoke_proc }.to raise_error(ArgumentError)
    end
  end
end
