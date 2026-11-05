# frozen_string_literal: true

require "datadog/di/spec_helper"
require "datadog/di"
require "tempfile"

# Tests verifying that targeted TracePoints are bound to the specific iseq
# object, not the source location. A TracePoint targeted at a compile_file
# iseq does NOT fire when the require-produced iseq for the same source
# executes (and vice versa). This matters for backfill_registry: registering
# a compile_file iseq instead of the require-produced iseq would cause
# probes to silently never fire.
#
# See: https://github.com/DataDog/dd-trace-rb/pull/5496#discussion_r3052752533
RSpec.describe "Targeted TracePoint iseq binding" do
  di_test

  # Use a tempfile to guarantee a fresh file that hasn't been required yet.
  let(:source_code) do
    <<~RUBY
      class CompileFileTestTarget
        def test_method
          a = 21
          a * 2
        end
      end
    RUBY
  end

  let(:tempfile) do
    Tempfile.new(["compile_file_test", ".rb"]).tap do |f|
      f.write(source_code)
      f.flush
    end
  end

  after do
    tempfile.close!
    Object.send(:remove_const, :CompileFileTestTarget) if defined?(CompileFileTestTarget)
  end

  it "trace point on compile_file iseq does NOT fire for require-produced code" do
    # 1. Compile the file (produces iseq without executing)
    compiled_iseq = RubyVM::InstructionSequence.compile_file(tempfile.path)

    # 2. Actually load the file (executes the code, defines the class)
    load tempfile.path

    # 3. Install a targeted trace point on the compile_file iseq
    fired = false
    tp = TracePoint.new(:line) { fired = true }
    tp.enable(target: compiled_iseq)

    # 4. Call the method (uses the require-produced iseq, not compile_file's)
    CompileFileTestTarget.new.test_method

    tp.disable

    # The trace point should NOT fire — it's targeted at a different iseq object.
    # This confirms that registering a compile_file iseq in backfill_registry
    # would cause probes to silently never fire.
    expect(fired).to be false
  end

  it "trace point on require-produced iseq DOES fire for require-produced code" do
    # Load the file to get the require-produced iseq
    load tempfile.path

    # Find the iseq for test_method
    method_iseq = RubyVM::InstructionSequence.of(CompileFileTestTarget.instance_method(:test_method))

    fired = false
    tp = TracePoint.new(:line) { fired = true }
    tp.enable(target: method_iseq)

    CompileFileTestTarget.new.test_method

    tp.disable

    # The trace point SHOULD fire — same iseq object
    expect(fired).to be true
  end
end
