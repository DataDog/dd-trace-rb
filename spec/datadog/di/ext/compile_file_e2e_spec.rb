# frozen_string_literal: true

require "datadog/di/spec_helper"
require "datadog/di"

# End-to-end test verifying that compile_file iseqs in object space do
# not cause probes to silently fail.
#
# LIMITATION: compile_file produces child iseqs (:method, :class) that
# are indistinguishable from require-produced children by type or
# first_lineno. If backfill_registry picks up a compile_file child
# iseq, a probe targeted at it will not fire (targeted TracePoints are
# bound to the specific iseq object). The first_lineno == 0 guard
# filters out compile_file :top iseqs, but not their children.
#
# This test verifies:
# 1. The :top iseq from compile_file is correctly rejected
# 2. When compile_file children are NOT present (the normal case —
#    compile_file references are dropped and children are GC'd), the
#    per-method fallback works correctly
#
# See: https://github.com/DataDog/dd-trace-rb/pull/5496#discussion_r3052752533

# Step 1: Load the test class before tracking starts.
require_relative "compile_file_e2e_test_class"

# Step 2: compile_file the same file. We do NOT hold the reference —
# in production, compile_file results are typically consumed and
# discarded. Without a reference, GC collects both the :top and its
# child iseqs.
RubyVM::InstructionSequence.compile_file(
  File.join(__dir__, "compile_file_e2e_test_class.rb"),
)

# Step 3: GC everything unreferenced — both the require-produced :top
# and the compile_file iseqs (top + children).
# This test intentionally depends on that GC behavior; preconditions are
# asserted in before(:all) below so we don't get false positives via
# whole-file matching.
GC.start
GC.start

RSpec.describe "compile_file iseq end-to-end probe test" do
  di_test

  before(:all) do
    skip "Test requires iseq_type (Ruby < 3.1)" unless Datadog::DI.respond_to?(:iseq_type)

    # Hard precondition: no :top iseqs survive for the target file.
    # If a :top iseq remains, probe installation can succeed via the
    # normal whole-file path and would not prove the fallback behavior.
    #
    # We also require method iseqs to survive so line probes still have
    # executable iseqs to target through per-method fallback.
    target = "compile_file_e2e_test_class.rb"
    iseqs = Datadog::DI.all_iseqs.select { |i| i.absolute_path&.end_with?(target) }
    types = iseqs.map { |i| Datadog::DI.iseq_type(i) }

    skip "A :top iseq survived GC (precondition failed)" if types.include?(:top)
    skip "No method iseqs found (precondition failed)" unless types.include?(:method)
  end

  let(:diagnostics_transport) do
    double(Datadog::DI::Transport::Diagnostics::Transport)
  end

  let(:input_transport) do
    double(Datadog::DI::Transport::Input::Transport)
  end

  before do
    allow(Datadog::DI::Transport::HTTP).to receive(:diagnostics).and_return(diagnostics_transport)
    allow(Datadog::DI::Transport::HTTP).to receive(:input).and_return(input_transport)
    allow(diagnostics_transport).to receive(:send_diagnostics)
    allow(input_transport).to receive(:send_input)
  end

  after do
    component.shutdown!
    Datadog::DI.deactivate_tracking!
  end

  let(:settings) do
    Datadog::Core::Configuration::Settings.new.tap do |settings|
      settings.remote.enabled = true
      settings.dynamic_instrumentation.enabled = true
      settings.dynamic_instrumentation.internal.development = true
      settings.dynamic_instrumentation.internal.propagate_all_exceptions = true
    end
  end

  let(:agent_settings) do
    instance_double_agent_settings_with_stubs
  end

  let(:logger) { logger_allowing_debug }

  let(:component) do
    Datadog::DI::Component.build(settings, agent_settings, logger).tap do |component|
      raise "Component failed to create" if component.nil?
    end
  end

  let(:probe_manager) do
    component.probe_manager
  end

  context "after compile_file iseqs are GC'd" do
    before do
      Datadog::DI.activate_tracking!
      allow(Datadog::DI).to receive(:current_component).and_return(component)
    end

    let(:probe) do
      Datadog::DI::Probe.new(
        id: "compile-file-e2e-1", type: :log,
        file: "compile_file_e2e_test_class.rb", line_no: 22,
        capture_snapshot: false,
      )
    end

    it "installs the probe via per-method iseq fallback" do
      expect(diagnostics_transport).to receive(:send_diagnostics)
      probe_manager.add_probe(probe)
      component.probe_notifier_worker.flush

      expect(probe_manager.probe_repository.installed_probes.length).to eq(1)
    end

    it "fires the probe when the target line executes" do
      expect(diagnostics_transport).to receive(:send_diagnostics)
      probe_manager.add_probe(probe)
      component.probe_notifier_worker.flush

      expect(component.probe_notifier_worker).to receive(:add_snapshot)
      expect(CompileFileE2eTestClass.new.test_method).to eq(42)
    end
  end
end
