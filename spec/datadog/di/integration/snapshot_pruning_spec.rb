require "datadog/di/spec_helper"
require "datadog/di"
require "json"

# End-to-end coverage for snapshot size pruning: a probe is installed, the
# target code runs, and the test asserts on the payload actually delivered
# to the snapshot input endpoint, exercising the real serializer through
# the real encoder.

class SnapshotPruningTestClass
  def capture_method(huge, small)
    small
  end
end

RSpec.describe "Snapshot size pruning integration" do
  di_test

  let(:diagnostics_transport) do
    double(Datadog::DI::Transport::Diagnostics::Transport)
  end

  # A real input transport, so the encoder runs. Chunk sending is stubbed,
  # so no request reaches the network.
  let(:input_transport) do
    Datadog::DI::Transport::HTTP.input(agent_settings: agent_settings, logger: logger, telemetry: nil)
  end

  let(:delivered_chunks) { [] }

  let(:agent_settings) do
    instance_double_agent_settings_with_stubs
  end

  let(:logger) { logger_allowing_debug }

  before do
    allow(Datadog::DI::Transport::HTTP).to receive(:diagnostics).and_return(diagnostics_transport)
    allow(Datadog::DI::Transport::HTTP).to receive(:input).and_return(input_transport)
    allow(diagnostics_transport).to receive(:send_diagnostics)
    allow(input_transport).to receive(:send_input_chunk) do |chunked_payload, _serialized_tags|
      delivered_chunks << chunked_payload
    end
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

  let(:component) do
    Datadog::DI::Component.build(settings, agent_settings, logger).tap do |component|
      if component.nil?
        raise "Component failed to create - unsuitable environment? Check log entries"
      end
      component.start!
    end
  end

  let(:probe_manager) do
    component.probe_manager
  end

  let(:probe) do
    Datadog::DI::Probe.new(id: "snapshot-pruning-probe", type: :log,
      type_name: "SnapshotPruningTestClass", method_name: "capture_method",
      capture_snapshot: true,
      max_capture_string_length: 2_000_000,)
  end

  before do
    allow(Datadog::DI).to receive(:current_component).and_return(component)
  end

  it "delivers a pruned snapshot within the size cap" do
    probe_manager.add_probe(probe)

    expect(SnapshotPruningTestClass.new.capture_method("x" * 2_000_000, "small")).to eq("small")

    component.probe_notifier_worker.flush

    expect(delivered_chunks.length).to eq(1)
    chunked_payload = delivered_chunks.first
    expect(chunked_payload.bytesize)
      .to be <= Datadog::DI::Transport::Input::Transport::MAX_SERIALIZED_SNAPSHOT_SIZE + 2

    snapshot = JSON.parse(chunked_payload).first
    arguments = snapshot.dig("debugger", "snapshot", "captures", "entry", "arguments")
    expect(arguments["arg1"]).to eq("pruned" => true)
    expect(arguments["arg2"]).to eq("type" => "String", "value" => "small")
  end
end
