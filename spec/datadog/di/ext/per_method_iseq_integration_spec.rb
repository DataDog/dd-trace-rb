# frozen_string_literal: true

require "datadog/di/spec_helper"
require "datadog/di"

# Load the test class BEFORE code tracking starts, then GC the top iseq.
# This simulates the common case where a gem's whole-file iseq has been
# garbage collected but per-method iseqs survive.
require_relative "per_method_iseq_integration_test_class"
GC.start
GC.start

RSpec.describe "Per-method iseq line probe integration" do
  di_test

  before(:all) do
    skip "Test requires iseq_type (Ruby < 3.1)" unless Datadog::DI.respond_to?(:iseq_type)

    # Verify that the top iseq was actually GC'd and only method iseq survives.
    target = "per_method_iseq_integration_test_class.rb"
    types = Datadog::DI.all_iseqs
      .select { |iseq| iseq.absolute_path&.end_with?(target) }
      .map { |iseq| Datadog::DI.iseq_type(iseq) }
    skip "Top iseq was not GC'd (test precondition failed)" if types.include?(:top)
    skip "No method iseqs found (test precondition failed)" unless types.include?(:method)
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

  context "line probe on file with only per-method iseqs" do
    before do
      Datadog::DI.activate_tracking!
      allow(Datadog::DI).to receive(:current_component).and_return(component)
    end

    let(:probe) do
      Datadog::DI::Probe.new(
        id: "per-method-test-1", type: :log,
        file: "per_method_iseq_integration_test_class.rb", line_no: 22,
        capture_snapshot: false,
      )
    end

    it "installs the probe using a per-method iseq" do
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
      expect(PerMethodIseqIntegrationTestClass.new.test_method).to eq(42)
    end

    context "with snapshot capture" do
      let(:probe) do
        Datadog::DI::Probe.new(
          id: "per-method-test-2", type: :log,
          file: "per_method_iseq_integration_test_class.rb", line_no: 22,
          capture_snapshot: true,
        )
      end

      it "captures local variables from the per-method iseq" do
        expect(diagnostics_transport).to receive(:send_diagnostics)
        probe_manager.add_probe(probe)

        payload = nil
        expect(component.probe_notifier_worker).to receive(:add_snapshot) do |payload_|
          payload = payload_
        end

        expect(PerMethodIseqIntegrationTestClass.new.test_method).to eq(42)
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
