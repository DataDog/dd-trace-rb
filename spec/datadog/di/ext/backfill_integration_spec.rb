# frozen_string_literal: true

require "datadog/di/spec_helper"
require "datadog/di"

# Load the test class BEFORE code tracking starts.
# This simulates the common case of application/gem code loaded at boot
# time before DI activates. Without backfill, line probes on this code
# would fail with DITargetNotDefined because the iseq is not in the
# CodeTracker registry.
require_relative "backfill_integration_test_class"

RSpec.describe "CodeTracker backfill integration" do
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

  context "line probe on pre-loaded file" do
    before do
      # Activate tracking AFTER the test class was loaded (at require_relative
      # above). The backfill in CodeTracker#start should recover the iseq
      # for backfill_integration_test_class.rb from the object space.
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
