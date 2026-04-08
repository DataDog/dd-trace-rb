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

  before(:all) do
    skip "Test requires iseq_type (Ruby < 3.1)" unless Datadog::DI.respond_to?(:iseq_type)
  end

  let(:tracker) { Datadog::DI::CodeTracker.new }

  after do
    tracker.stop
  end

  # Simulate the scenario: a file is loaded (require), then someone
  # also calls compile_file on it and holds the reference. The require-
  # produced :top iseq gets GC'd (normal behavior), but the compile_file
  # :top iseq survives because a reference is held. backfill_registry
  # should NOT register the compile_file iseq.
  it "does not register compile_file iseqs that would cause probes to never fire" do
    # Create a temp source file
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

    tracker.backfill_registry

    # If backfill registered the compile_file iseq, a targeted TracePoint
    # on it would never fire when the actual method executes.
    result = tracker.iseqs_for_path_suffix(tempfile.path)

    if result
      _path, registered_iseq = result

      # Verify: does a trace point on the registered iseq actually fire?
      fired = false
      tp = TracePoint.new(:line) { fired = true }
      tp.enable(target: registered_iseq)

      BackfillCompileTestClass.new.test_method

      tp.disable

      # If this fails, backfill registered a compile_file iseq that
      # produces a non-firing probe — the bot's concern is confirmed.
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
