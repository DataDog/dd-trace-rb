require "datadog/di/spec_helper"
require "datadog/di"
require "json"

# Target of the snapshot pruning integration probes.
class SnapshotPruningTestClass
  # Returns 100 arrays of 100 strings of 300 characters, which serialize
  # to about 3.1 MB at default capture settings.
  def build_matrix
    Array.new(100) { Array.new(100) { "x" * 300 } }
  end
end

RSpec.describe "Snapshot size pruning integration" do
  di_test

  let(:diagnostics_transport) do
    instance_double(Datadog::DI::Transport::Diagnostics::Transport, send_diagnostics: nil)
  end

  let(:di_logger) { Datadog::DI::Logger.new(settings, logger) }

  let(:guardrails_telemetry) do
    Datadog::DI::GuardrailsTelemetry.new(settings: settings, logger: di_logger, telemetry: nil)
  end

  let(:input_transport) do
    Datadog::DI::Transport::HTTP.input(agent_settings: agent_settings, logger: di_logger, telemetry: nil,
      guardrails_telemetry: guardrails_telemetry)
  end

  let(:agent_settings) { instance_double_agent_settings_with_stubs }

  let(:logger) { logger_allowing_debug }

  let(:sent_chunks) { Queue.new }

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
      raise "Component failed to create - unsuitable environment? Check log entries" if component.nil?

      component.start!
    end
  end

  let(:probe_rate_limit) { nil }

  let(:probe) do
    Datadog::DI::Probe.new(id: "snapshot-pruning-probe", type: :log,
      type_name: "SnapshotPruningTestClass", method_name: "build_matrix",
      capture_snapshot: true, rate_limit: probe_rate_limit)
  end

  let(:cap) { Datadog::DI::Transport::Input::Transport::SNAPSHOT_SIZE_CAP }

  before do
    allow(Datadog::DI::Transport::HTTP).to receive_messages(diagnostics: diagnostics_transport, input: input_transport)
    allow(input_transport).to receive(:send_input_chunk) { |chunked_payload, _serialized_tags| sent_chunks << chunked_payload }
    allow(Datadog::DI).to receive(:current_component).and_return(component)
    component.probe_manager.add_probe(probe)
  end

  after do
    component.shutdown!
  end

  it "sends the pruned snapshot within the size cap" do
    SnapshotPruningTestClass.new.build_matrix
    component.probe_notifier_worker.flush

    expect(sent_chunks.size).to eq 1
    chunk = sent_chunks.pop
    # The request body is the snapshot inside the two array brackets.
    expect(chunk.bytesize - 2).to be <= cap
    snapshots = JSON.parse(chunk)
    expect(snapshots.length).to eq 1
    inner_arrays = snapshots.first.dig("debugger", "snapshot", "captures", "return", "arguments", "@return", "elements")
    expect(inner_arrays.flat_map { |inner| inner["elements"] }).to include("pruned" => true)
    expect(inner_arrays.first["elements"].length).to eq 100
    expect(inner_arrays.first["elements"]).not_to include("pruned" => true)

    worker = component.probe_notifier_worker
    expect(worker.pruned_snapshot_count).to eq 1
    expect(worker.last_pruned_at).to be_a(Float)
  end

  context "with two pruned snapshots in one batch" do
    # The probe's token bucket starts full, so a rate limit of 3 admits the
    # three firings of the example.
    let(:probe_rate_limit) { 3 }

    before do
      settings.dynamic_instrumentation.internal.min_send_interval = 1
    end

    it "sends each snapshot in its own request body within the per-event limit" do
      send_input_batches = []
      allow(input_transport).to receive(:send_input).and_wrap_original do |original, payload, *args, **kwargs|
        send_input_batches << payload.length
        original.call(payload, *args, **kwargs)
      end

      SnapshotPruningTestClass.new.build_matrix
      # Waiting for the first send makes the worker wait out the minimum
      # send interval before its next send.
      Timeout.timeout(10) { sent_chunks.pop }

      SnapshotPruningTestClass.new.build_matrix
      SnapshotPruningTestClass.new.build_matrix
      component.probe_notifier_worker.flush

      expect(send_input_batches).to eq [1, 2]
      expect(sent_chunks.size).to eq 2
      2.times do
        expect(sent_chunks.pop.bytesize).to be <= Datadog::DI::Transport::Input::Transport::MAX_SERIALIZED_SNAPSHOT_SIZE
      end
    end
  end
end
