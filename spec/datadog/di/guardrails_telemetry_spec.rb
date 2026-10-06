require "datadog/di/spec_helper"
require "datadog/di/guardrails_telemetry"
require "datadog/di/probe"

RSpec.describe Datadog::DI::GuardrailsTelemetry do
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }

  let(:guardrails_telemetry) do
    described_class.new(telemetry: telemetry)
  end

  describe ".probe_type_tag" do
    let(:capture_snapshot) { true }

    let(:probe) do
      Datadog::DI::Probe.new(id: "p1", type: :log, type_name: "C",
        method_name: "m", capture_snapshot: capture_snapshot,)
    end

    it "returns snapshot for a snapshot probe" do
      expect(described_class.probe_type_tag(probe)).to eq("snapshot")
    end

    context "for a log probe" do
      let(:capture_snapshot) { false }

      it "returns log" do
        expect(described_class.probe_type_tag(probe)).to eq("log")
      end
    end
  end

  describe ".event_type_tag" do
    it "maps snapshot to snapshot" do
      expect(described_class.event_type_tag(:snapshot)).to eq("snapshot")
    end

    it "maps log to log" do
      expect(described_class.event_type_tag(:log)).to eq("log")
    end

    it "maps status to diagnostic" do
      expect(described_class.event_type_tag(:status)).to eq("diagnostic")
    end

    it "raises ArgumentError for unknown event types" do
      expect { described_class.event_type_tag(:bogus) }.to raise_error(ArgumentError, /Unknown DI event type/)
    end
  end

  describe "#skipped" do
    it "is a no-op when telemetry is nil" do
      expect(described_class.new(telemetry: nil).skipped(
        reason: described_class::Reason::RATE_LIMIT_PROBE, probe_type: "snapshot",
      )).to be_nil
    end

    it "emits the canonical skipped metric with reason and probe_type tags" do
      expect(telemetry).to receive(:inc).with("dynamic_instrumentation", "guardrails.events.skipped", 1,
        tags: {reason: "rateLimitProbe", probe_type: "snapshot"},)

      guardrails_telemetry.skipped(
        reason: described_class::Reason::RATE_LIMIT_PROBE,
        probe_type: "snapshot",
      )
    end

    it "reuses a single frozen tag hash for a reason and probe_type pair" do
      emitted_tags = []
      allow(telemetry).to receive(:inc) do |_namespace, _name, _value, tags:|
        emitted_tags << tags
      end

      2.times do
        guardrails_telemetry.skipped(
          reason: described_class::Reason::RATE_LIMIT_PROBE,
          probe_type: "snapshot",
        )
      end

      expect(emitted_tags.length).to eq(2)
      expect(emitted_tags.first).to equal(emitted_tags.last)
      expect(emitted_tags.first).to be_frozen
    end
  end

  describe "#dropped" do
    it "is a no-op when telemetry is nil" do
      expect(described_class.new(telemetry: nil).dropped(
        reason: described_class::Reason::QUEUE_FULL, event_type: "snapshot", bytes: 100,
      )).to be_nil
    end

    it "emits only the dropped metric when bytes is omitted" do
      expect(telemetry).to receive(:inc).with("dynamic_instrumentation", "guardrails.events.dropped", 1,
        tags: {reason: "queueFull", event_type: "snapshot"},)

      guardrails_telemetry.dropped(
        reason: described_class::Reason::QUEUE_FULL,
        event_type: "snapshot",
      )
    end

    it "emits the dropped and dropped_bytes metrics when bytes is provided" do
      expect(telemetry).to receive(:inc).with("dynamic_instrumentation", "guardrails.events.dropped", 1,
        tags: {reason: "payloadTooLarge", event_type: "snapshot"},)
      expect(telemetry).to receive(:inc).with("dynamic_instrumentation", "guardrails.queue.dropped_bytes", 2048,
        tags: {reason: "payloadTooLarge", event_type: "snapshot"},)

      guardrails_telemetry.dropped(
        reason: described_class::Reason::PAYLOAD_TOO_LARGE,
        event_type: "snapshot", bytes: 2048,
      )
    end
  end
end
