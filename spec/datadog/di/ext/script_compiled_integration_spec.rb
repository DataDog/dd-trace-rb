# frozen_string_literal: true

require "datadog/di/spec_helper"
require "datadog/di"

# End-to-end test for the primary :script_compiled code path.
# File loaded AFTER tracking starts → captured by TracePoint →
# probe installed → probe fires → snapshot captured.
#
# This is the normal path that most DI probes use. The backfill path
# (tested in backfill_integration_spec.rb) is for files loaded before
# DI activates.
RSpec.describe "script_compiled integration" do
  di_test

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
    Object.send(:remove_const, :ScriptCompiledIntegrationTestClass) if defined?(ScriptCompiledIntegrationTestClass)
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

  let(:test_file) do
    File.join(__dir__, "script_compiled_integration_test_class.rb")
  end

  context "file loaded after tracking starts" do
    before do
      # Start tracking BEFORE loading the file — this is the normal path.
      Datadog::DI.activate_tracking!
      allow(Datadog::DI).to receive(:current_component).and_return(component)

      # Load the file. :script_compiled fires and captures the iseq.
      load test_file
    end

    it "captures the file in CodeTracker registry" do
      tracker = Datadog::DI.code_tracker
      expect(tracker).not_to be_nil

      result = tracker.iseqs_for_path_suffix("script_compiled_integration_test_class.rb")
      expect(result).not_to be_nil,
        "CodeTracker registry does not contain the test file after loading"

      path, iseq = result
      expect(path).to end_with("script_compiled_integration_test_class.rb")
      expect(iseq).to be_a(RubyVM::InstructionSequence)
    end

    it "the registered iseq is the one Ruby executes (TracePoint fires)" do
      tracker = Datadog::DI.code_tracker
      result = tracker.iseqs_for_path_suffix("script_compiled_integration_test_class.rb")
      expect(result).not_to be_nil

      _path, iseq = result

      fired = false
      tp = TracePoint.new(:line) { fired = true }
      tp.enable(target: iseq)

      ScriptCompiledIntegrationTestClass.new.test_method

      tp.disable

      expect(fired).to be(true),
        "TracePoint on the :script_compiled iseq did not fire"
    end

    it "installs a probe on the file" do
      probe = Datadog::DI::Probe.new(
        id: "script-compiled-e2e-1", type: :log,
        file: "script_compiled_integration_test_class.rb", line_no: 22,
        capture_snapshot: false,
      )

      expect(diagnostics_transport).to receive(:send_diagnostics)
      probe_manager.add_probe(probe)
      component.probe_notifier_worker.flush

      installed = probe_manager.probe_repository.installed_probes
      expect(installed.length).to eq(1),
        "Expected 1 installed probe, got #{installed.length}"
    end

    it "fires the probe when the target line executes" do
      probe = Datadog::DI::Probe.new(
        id: "script-compiled-e2e-2", type: :log,
        file: "script_compiled_integration_test_class.rb", line_no: 22,
        capture_snapshot: false,
      )

      expect(diagnostics_transport).to receive(:send_diagnostics)
      probe_manager.add_probe(probe)
      component.probe_notifier_worker.flush

      expect(component.probe_notifier_worker).to receive(:add_snapshot)
      result = ScriptCompiledIntegrationTestClass.new.test_method
      expect(result).to eq(42)
    end

    it "captures local variables from the probe" do
      probe = Datadog::DI::Probe.new(
        id: "script-compiled-e2e-3", type: :log,
        file: "script_compiled_integration_test_class.rb", line_no: 22,
        capture_snapshot: true,
      )

      expect(diagnostics_transport).to receive(:send_diagnostics)
      probe_manager.add_probe(probe)

      payload = nil
      expect(component.probe_notifier_worker).to receive(:add_snapshot) do |payload_|
        payload = payload_
      end

      result = ScriptCompiledIntegrationTestClass.new.test_method
      expect(result).to eq(42)
      component.probe_notifier_worker.flush

      expect(payload).to be_a(Hash),
        "Snapshot payload is nil — probe did not fire"

      captures = payload.dig(:debugger, :snapshot, :captures)
      expect(captures).not_to be_nil,
        "Snapshot has no captures"

      locals = captures.dig(:lines, 22, :locals)
      expect(locals).not_to be_nil,
        "Snapshot has no locals for line 22"

      expect(locals).to include(:a),
        "Local variable :a not captured. Locals: #{locals.keys}"

      expect(locals[:a]).to eq({type: "Integer", value: "21"}),
        "Local variable :a has wrong value: #{locals[:a].inspect}"
    end
  end
end
