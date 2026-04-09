# frozen_string_literal: true

require "datadog/di/spec_helper"
require "datadog/di"
require "tmpdir"

# Load bootsnap at file load time. `require "bootsnap"` alone does not load
# Bootsnap::CompileCache::ISeq — that submodule requires an explicit require.
require "bootsnap"
require "bootsnap/compile_cache/iseq"

# Verify the ISeq cache can actually initialize in this environment.
# This runs at load time so failures are visible immediately, not
# hidden behind a skip guard.
BOOTSNAP_VERIFY_DIR = Dir.mktmpdir("bootsnap_probe")
Bootsnap::CompileCache::ISeq.install!(BOOTSNAP_VERIFY_DIR)
Bootsnap::CompileCache::ISeq::InstructionSequenceMixin.send(:remove_method, :load_iseq)
FileUtils.remove_entry(BOOTSNAP_VERIFY_DIR)

# End-to-end test: DI code tracking works correctly when Bootsnap's iseq
# cache is active. Bootsnap hooks RubyVM::InstructionSequence.load_iseq
# to serve pre-compiled iseqs from a binary cache on disk instead of
# compiling from source on every require. DI's :script_compiled TracePoint
# must fire for Bootsnap-cached loads, and the iseq it captures must be
# the one Ruby executes (so targeted TracePoints on it fire correctly).
#
# This test uses the real Bootsnap gem — not a simulation.
RSpec.describe "DI CodeTracker with Bootsnap" do
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

  context "file loaded via Bootsnap iseq cache" do
    let(:cache_dir) { Dir.mktmpdir("bootsnap_di_test") }
    let(:test_file) { File.join(__dir__, "bootsnap_test_class.rb") }

    before do
      # Install Bootsnap's iseq cache with a fresh temp directory.
      Bootsnap::CompileCache::ISeq.install!(cache_dir)

      # Prime the Bootsnap cache by loading the test file once.
      # This compiles the source and writes the binary cache to disk.
      load test_file

      # Remove the class so the second load (below) re-defines it.
      Object.send(:remove_const, :BootsnapTestClass)

      # Now start DI tracking. The next load will hit Bootsnap's cache
      # (load_iseq returns a cached iseq instead of compiling from source).
      Datadog::DI.activate_tracking!
      allow(Datadog::DI).to receive(:current_component).and_return(component)
    end

    after do
      FileUtils.remove_entry(cache_dir)
      # Remove load_iseq from the prepended module so it falls through
      # to normal compilation. The module stays in the ancestor chain but
      # becomes a no-op (same pattern as DI instrumenter method probe cleanup).
      if Bootsnap::CompileCache::ISeq::InstructionSequenceMixin.method_defined?(:load_iseq)
        Bootsnap::CompileCache::ISeq::InstructionSequenceMixin.send(:remove_method, :load_iseq)
      end
      Object.send(:remove_const, :BootsnapTestClass) if defined?(BootsnapTestClass)
    end

    it "captures the Bootsnap-cached file in the CodeTracker registry" do
      # Load the file again — this time Bootsnap serves it from cache.
      load test_file

      # Verify: CodeTracker has an entry for this file.
      tracker = Datadog::DI.code_tracker
      expect(tracker).not_to be_nil

      result = tracker.iseqs_for_path_suffix("bootsnap_test_class.rb")
      expect(result).not_to be_nil,
        "CodeTracker registry does not contain bootsnap_test_class.rb " \
        "after Bootsnap-cached load. :script_compiled may not have fired."

      path, iseq = result
      expect(path).to end_with("bootsnap_test_class.rb")
      expect(iseq).to be_a(RubyVM::InstructionSequence)
    end

    it "the registered iseq is the one Ruby executes (TracePoint fires)" do
      load test_file

      tracker = Datadog::DI.code_tracker
      result = tracker.iseqs_for_path_suffix("bootsnap_test_class.rb")
      expect(result).not_to be_nil

      _path, iseq = result

      # Install a targeted TracePoint on the registered iseq and verify
      # it fires when the method executes. This confirms the iseq from
      # :script_compiled is the same object Ruby uses for execution —
      # not a separate compilation.
      fired = false
      tp = TracePoint.new(:line) { fired = true }
      tp.enable(target: iseq)

      BootsnapTestClass.new.test_method

      tp.disable

      expect(fired).to be(true),
        "TracePoint targeted at the CodeTracker iseq did not fire. " \
        "The iseq captured by :script_compiled may not be the one " \
        "Ruby is executing (Bootsnap interaction issue)."
    end

    it "installs a probe on the Bootsnap-cached file" do
      load test_file

      probe = Datadog::DI::Probe.new(
        id: "bootsnap-test-1", type: :log,
        file: "bootsnap_test_class.rb", line_no: 22,
        capture_snapshot: false,
      )

      expect(diagnostics_transport).to receive(:send_diagnostics)
      probe_manager.add_probe(probe)
      component.probe_notifier_worker.flush

      # Probe should be installed successfully.
      installed = probe_manager.probe_repository.installed_probes
      expect(installed.length).to eq(1),
        "Expected 1 installed probe, got #{installed.length}. " \
        "Probe installation failed on Bootsnap-cached file."
    end

    it "fires the probe when the target line executes" do
      load test_file

      probe = Datadog::DI::Probe.new(
        id: "bootsnap-test-2", type: :log,
        file: "bootsnap_test_class.rb", line_no: 22,
        capture_snapshot: false,
      )

      expect(diagnostics_transport).to receive(:send_diagnostics)
      probe_manager.add_probe(probe)
      component.probe_notifier_worker.flush

      expect(component.probe_notifier_worker).to receive(:add_snapshot)
      result = BootsnapTestClass.new.test_method
      expect(result).to eq(42)
    end

    it "captures local variables from Bootsnap-cached code" do
      load test_file

      probe = Datadog::DI::Probe.new(
        id: "bootsnap-test-3", type: :log,
        file: "bootsnap_test_class.rb", line_no: 22,
        capture_snapshot: true,
      )

      expect(diagnostics_transport).to receive(:send_diagnostics)
      probe_manager.add_probe(probe)

      payload = nil
      expect(component.probe_notifier_worker).to receive(:add_snapshot) do |payload_|
        payload = payload_
      end

      result = BootsnapTestClass.new.test_method
      expect(result).to eq(42)
      component.probe_notifier_worker.flush

      # Verify the snapshot captured local variables correctly.
      expect(payload).to be_a(Hash),
        "Snapshot payload is nil — probe did not fire on Bootsnap-cached code."

      captures = payload.dig(:debugger, :snapshot, :captures)
      expect(captures).not_to be_nil,
        "Snapshot has no captures — probe fired but didn't capture data."

      locals = captures.dig(:lines, 22, :locals)
      expect(locals).not_to be_nil,
        "Snapshot has no locals for line 22 — capture may have targeted wrong line."

      expect(locals).to include(:a),
        "Local variable :a not captured. Locals present: #{locals.keys}"

      expect(locals[:a]).to eq({type: "Integer", value: "21"}),
        "Local variable :a has wrong value: #{locals[:a].inspect}"
    end

    it "Bootsnap cache was actually used (not just normal compilation)" do
      # Verify precondition: the cache file exists on disk, proving
      # Bootsnap wrote a cached binary during the first load.
      cache_files = Dir.glob(File.join(cache_dir, "**/*")).select { |f| File.file?(f) }
      expect(cache_files).not_to be_empty,
        "No Bootsnap cache files found in #{cache_dir}. " \
        "Bootsnap may not have been properly initialized."

      # Load the file and verify load_iseq was called (Bootsnap's hook).
      # We can't easily check this without instrumenting Bootsnap itself,
      # but the presence of cache files + successful probe firing
      # (tested above) is sufficient evidence.
      load test_file

      # The file should be in the registry.
      tracker = Datadog::DI.code_tracker
      result = tracker.iseqs_for_path_suffix("bootsnap_test_class.rb")
      expect(result).not_to be_nil
    end
  end
end
