# frozen_string_literal: true

require "datadog/di/spec_helper"
require "datadog/di"

# Load the test class BEFORE code tracking starts.
# This simulates the common case of application/gem code loaded at boot
# time before DI activates. Without backfill, line probes on this code
# would fail with DITargetNotDefined because the iseq is not in the
# CodeTracker registry.
#
# Load the test class with GC disabled so the top-level (:top) iseq
# survives long enough to be captured below. The top-level iseq is not
# referenced by any constant or method after loading completes — only
# class/method child iseqs survive via BackfillIntegrationTestClass.
GC.disable
require_relative "backfill_integration_test_class"

# Keep the top-level iseq alive across tests by holding a reference.
# Without this, deactivate_tracking! in the after block clears the
# registry (the only reference), and GC can collect the iseq before
# the next test's backfill_registry walks object space.
# Ruby 3.2.9+ creates dummy iseqs (no bytecode, empty trace_points)
# for profiler frames during require. Filter them out — only the real
# top-level iseq has trace events and can target child iseq lines.
BACKFILL_TEST_TOP_ISEQ = Datadog::DI.file_iseqs.find { |i|
  i.absolute_path&.end_with?("backfill_integration_test_class.rb") &&
    !i.trace_points.empty? &&
    (Datadog::DI.respond_to?(:iseq_type) ? Datadog::DI.iseq_type(i) == :top : i.first_lineno == 0)
}
GC.enable

RSpec.describe "CodeTracker backfill integration" do
  di_test

  let(:diagnostics_transport) do
    instance_double(Datadog::DI::Transport::Diagnostics::Transport)
  end

  let(:input_transport) do
    instance_double(Datadog::DI::Transport::Input::Transport)
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

  context "line probe on pre-loaded file" do
    before do
      # Activate tracking AFTER the test class was loaded (at require_relative
      # above). The backfill in CodeTracker#start should recover the iseq
      # for backfill_integration_test_class.rb from the object space.
      # BACKFILL_TEST_TOP_ISEQ (set above) keeps the top-level iseq alive
      # so backfill_registry can find it across tests.
      Datadog::DI.activate_tracking!
      allow(Datadog::DI).to receive(:current_component).and_return(component)
    end

    let(:probe) do
      Datadog::DI::Probe.new(
        id: "backfill-test-1", type: :log,
        file: "backfill_integration_test_class.rb", line_no: 22,
        capture_snapshot: false,
      )
    end

    it "backfills the iseq and allows the probe to be installed" do
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
      expect(BackfillIntegrationTestClass.new.test_method).to eq(42)
    end

    context "when a dummy profiler iseq exists in object space" do
      # DI.create_dummy_iseq calls rb_iseq_alloc_with_dummy_path (Ruby
      # 3.2.9+) to create a real IMEMO iseq with iseq_size == 0 in the
      # heap. all_iseqs finds it during the object space walk. Without
      # the trace_points.empty? filter, backfill_registry would store
      # the dummy instead of the real iseq.
      before do
        # rb_iseq_alloc_with_dummy_path was backported to Ruby 3.2.9
        # and exists natively in 3.3+. On older Rubies, dummy profiler
        # iseqs are never created, so this scenario cannot occur.
        skip "requires Ruby 3.2.9+ (rb_iseq_alloc_with_dummy_path)" unless Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.2.9")
      end

      it "backfill_registry skips the dummy and stores the real iseq" do
        # Deactivate tracking so we can inject the dummy before backfill
        Datadog::DI.deactivate_tracking!

        # Create a real dummy iseq with the same path as the test class
        real_path = File.join(__dir__, "backfill_integration_test_class.rb")
        dummy = Datadog::DI.create_dummy_iseq(real_path)
        expect(dummy.trace_points).to be_empty

        # Re-activate tracking — backfill_registry runs, finds both
        # the dummy and real iseq in object space
        Datadog::DI.activate_tracking!

        code_tracker = Datadog::DI.code_tracker
        result = code_tracker.iseqs_for_path_suffix("backfill_integration_test_class.rb")
        expect(result).not_to be_nil
        _, stored_iseq = result

        # The stored iseq must be the real one (non-empty trace_points),
        # not the dummy
        expect(stored_iseq.trace_points).not_to be_empty
        expect(stored_iseq).not_to equal(dummy)
      end
    end

    context "with snapshot capture" do
      let(:probe) do
        Datadog::DI::Probe.new(
          id: "backfill-test-2", type: :log,
          file: "backfill_integration_test_class.rb", line_no: 22,
          capture_snapshot: true,
        )
      end

      it "captures local variables from the backfilled iseq" do
        expect(diagnostics_transport).to receive(:send_diagnostics)
        probe_manager.add_probe(probe)

        payload = nil
        expect(component.probe_notifier_worker).to receive(:add_snapshot) do |payload_|
          payload = payload_
        end

        expect(BackfillIntegrationTestClass.new.test_method).to eq(42)
        component.probe_notifier_worker.flush

        expect(payload).to be_a(Hash)
        captures = payload.dig(:debugger, :snapshot, :captures)
        locals = captures.dig(:lines, 22, :locals)
        expect(locals).to include(:a)
        expect(locals[:a]).to eq({type: "Integer", value: "21"})
      end
    end
  end
end
