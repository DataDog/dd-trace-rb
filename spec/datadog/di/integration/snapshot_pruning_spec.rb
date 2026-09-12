require "datadog/di/spec_helper"
require "datadog/di"
require "json"

class SnapshotPruningIntegrationTestClass
  def big_argument_method(items)
    items.length
  end
end

RSpec.describe "DI snapshot pruning integration" do
  di_test

  let(:diagnostics_transport) do
    double(Datadog::DI::Transport::Diagnostics::Transport)
  end

  # Real input transport: send_input runs for real (encode + prune +
  # chunk) so the pruning path is exercised end to end, while
  # send_input_chunk is captured instead of hitting the network.
  let(:input_transport) do
    Datadog::DI::Transport::HTTP.input(
      agent_settings: agent_settings,
      logger: logger,
      telemetry: nil,
    )
  end

  let(:chunks) { [] }

  before do
    # Build the real transport before intercepting HTTP.input so the
    # notifier worker reuses this instance.
    input_transport
    allow(Datadog::DI::Transport::HTTP).to receive(:diagnostics).and_return(diagnostics_transport)
    allow(Datadog::DI::Transport::HTTP).to receive(:input).and_return(input_transport)
    allow(diagnostics_transport).to receive(:send_diagnostics)
    allow(input_transport).to receive(:send_input_chunk) do |payload, _tags|
      chunks << payload
    end
    # Shrink the per-event cap so an oversized capture exceeds it and
    # gets pruned, while the snapshot envelope alone still fits under it.
    stub_const("Datadog::DI::Transport::Input::Transport::MAX_SERIALIZED_SNAPSHOT_SIZE", 20_000)
  end

  after do
    component.shutdown!
  end

  let(:settings) do
    Datadog::Core::Configuration::Settings.new.tap do |settings|
      settings.remote.enabled = true
      settings.dynamic_instrumentation.enabled = true
      settings.dynamic_instrumentation.internal.development = true
      settings.dynamic_instrumentation.internal.propagate_all_exceptions = true
    end
  end

  let(:instrumenter) { component.instrumenter }
  let(:probe_manager) { component.probe_manager }
  let(:agent_settings) { instance_double_agent_settings }
  let(:logger) { logger_allowing_debug }

  let(:component) do
    Datadog::DI::Component.build(settings, agent_settings, logger).tap do |component|
      if component.nil?
        raise "Component failed to create - unsuitable environment? Check log entries"
      end
      component.start!
    end
  end

  let(:probe) do
    Datadog::DI::Probe.new(id: "prune-1", type: :log,
      type_name: "SnapshotPruningIntegrationTestClass",
      method_name: "big_argument_method",
      capture_snapshot: true,)
  end

  it "prunes an oversized snapshot and delivers the envelope" do
    probe_manager.add_probe(probe)
    expect(component.probe_notifier_worker).to receive(:add_snapshot).once.and_call_original
    expect(SnapshotPruningIntegrationTestClass.new.big_argument_method(Array.new(100) { |i| "x" * 255 })).to eq(100)
    component.probe_notifier_worker.flush

    aggregate_failures do
      expect(chunks).not_to be_empty
      delivered = chunks.join
      expect(delivered.bytesize).to be <= 20_000
      expect(delivered).to include("\"pruned\":true")
      parsed = JSON.parse(delivered)
      snapshot = parsed.fetch(0)
      expect(snapshot.dig("debugger", "snapshot", "probe", "id")).to eq("prune-1")
      expect(snapshot.dig("debugger", "snapshot", "stack")).to be_an(Array)
    end
  end
end
