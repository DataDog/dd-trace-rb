# frozen_string_literal: true

require "datadog/di/spec_helper"
require "datadog/di"
require "tempfile"

# Regression test for the scenario where a compile_file iseq pollutes
# the backfill registry. Targeted TracePoints are bound to the specific
# iseq object — a TracePoint on a compile_file iseq does NOT fire when
# the require-produced iseq executes. If backfill_registry registers a
# compile_file iseq, probes installed against it silently never fire.
#
# See: https://github.com/DataDog/dd-trace-rb/pull/5496#discussion_r3052752533
RSpec.describe "backfill_registry with compile_file iseqs" do
  di_test

  let(:tracker) { Datadog::DI::CodeTracker.new }

  after do
    tracker.stop
  end

  # Helper: create a temp file, load it, compile_file it, GC the
  # require-produced :top iseq, then stub file_iseqs to return only
  # the compile_file iseq.
  def setup_compile_file_scenario
    tempfile = Tempfile.new(["backfill_compile_test", ".rb"])
    tempfile.write(<<~RUBY)
      class BackfillCompileTestClass
        def test_method
          a = 21
          a * 2
        end
      end
    RUBY
    tempfile.flush

    # Load the file (defines the class, produces a :top iseq)
    load tempfile.path

    # Also compile_file it (produces a separate :top iseq object)
    compiled_iseq = RubyVM::InstructionSequence.compile_file(tempfile.path)

    # GC the require-produced :top iseq (it has no references after loading)
    GC.start
    GC.start

    # Now the compile_file :top iseq is the only :top in object space for
    # this path (the require-produced one was GC'd). Stub file_iseqs to
    # return only the compile_file iseq, simulating what all_iseqs would
    # find in object space.
    allow(Datadog::DI).to receive(:file_iseqs).and_return([compiled_iseq])

    tempfile
  end

  # Simulate the scenario: a file is loaded (require), then someone
  # also calls compile_file on it and holds the reference. The require-
  # produced :top iseq gets GC'd (normal behavior), but the compile_file
  # :top iseq survives because a reference is held. backfill_registry
  # should NOT register the compile_file iseq.
  context "with iseq_type (Ruby 3.1+)" do
    before(:all) do
      skip "Test requires iseq_type (Ruby >= 3.1 only)" unless Datadog::DI.respond_to?(:iseq_type)
    end

    it "does not register compile_file iseqs that would cause probes to never fire" do
      tempfile = setup_compile_file_scenario

      tracker.backfill_registry

      result = tracker.iseqs_for_path_suffix(tempfile.path)

      expect(result).to be_nil,
        "backfill_registry should not register compile_file iseqs, " \
        "but registered iseq for: #{result&.first}"

      if result
        _path, registered_iseq = result

        # Verify: does a trace point on the registered iseq actually fire?
        fired = false
        tp = TracePoint.new(:line) { fired = true }
        tp.enable(target: registered_iseq)

        BackfillCompileTestClass.new.test_method

        tp.disable

        expect(fired).to be(true),
          "backfill_registry registered an iseq that does not fire when " \
          "the actual code executes. This is likely a compile_file iseq " \
          "rather than the require-produced iseq."
      end
    ensure
      Object.send(:remove_const, :BackfillCompileTestClass) if defined?(BackfillCompileTestClass)
      tempfile&.close
      tempfile&.unlink
    end
  end

  # On Ruby < 3.1, backfill_registry uses the first_lineno == 0
  # heuristic. compile_file produces iseqs with first_lineno == 1,
  # so they are excluded by the same check. This test verifies the
  # fallback path works on all supported Ruby versions.
  context "with first_lineno fallback (all Ruby versions)" do
    it "does not register compile_file iseqs via first_lineno check" do
      tempfile = setup_compile_file_scenario

      # Force the first_lineno fallback by stubbing iseq_type away
      allow(Datadog::DI).to receive(:respond_to?).and_call_original
      allow(Datadog::DI).to receive(:respond_to?).with(:iseq_type).and_return(false)

      tracker.backfill_registry

      result = tracker.iseqs_for_path_suffix(tempfile.path)

      expect(result).to be_nil,
        "backfill_registry (first_lineno fallback) should not register " \
        "compile_file iseqs, but registered iseq for: #{result&.first}"
    ensure
      Object.send(:remove_const, :BackfillCompileTestClass) if defined?(BackfillCompileTestClass)
      tempfile&.close
      tempfile&.unlink
    end
  end
end
