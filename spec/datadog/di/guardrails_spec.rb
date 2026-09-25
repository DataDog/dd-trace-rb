require "datadog/di/spec_helper"
require "datadog/di/guardrails"
require "datadog/di/probe"

RSpec.describe Datadog::DI::Guardrails do
  describe ".probe_type_tag" do
    it "returns snapshot for a snapshot probe" do
      probe = Datadog::DI::Probe.new(id: "p1", type: :log, type_name: "C",
        method_name: "m", capture_snapshot: true)
      expect(described_class.probe_type_tag(probe)).to eq("snapshot")
    end

    it "returns log for a log probe" do
      probe = Datadog::DI::Probe.new(id: "p1", type: :log, type_name: "C",
        method_name: "m", capture_snapshot: false)
      expect(described_class.probe_type_tag(probe)).to eq("log")
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

  describe ".skipped" do
    it "tolerates nil telemetry" do
      expect do
        described_class.skipped(nil, reason: described_class::Reason::RATE_LIMIT_PROBE,
          probe_type: "snapshot")
      end.not_to raise_error
    end

    it "emits the canonical skipped metric with reason and probe_type tags" do
      telemetry = instance_double(Datadog::Core::Telemetry::Component)
      expect_guardrails_metric(telemetry, name: "guardrails.events.skipped", value: 1,
        tags: {reason: "rateLimitProbe", probe_type: "snapshot"})

      described_class.skipped(telemetry, reason: described_class::Reason::RATE_LIMIT_PROBE,
        probe_type: "snapshot")
    end
  end

  describe ".dropped" do
    it "tolerates nil telemetry" do
      expect do
        described_class.dropped(nil, reason: described_class::Reason::QUEUE_FULL,
          event_type: "snapshot", bytes: 100)
      end.not_to raise_error
    end

    it "emits only the dropped metric when bytes is omitted" do
      telemetry = instance_double(Datadog::Core::Telemetry::Component)
      expect_guardrails_metric(telemetry, name: "guardrails.events.dropped", value: 1,
        tags: {reason: "queueFull", event_type: "snapshot"})

      described_class.dropped(telemetry, reason: described_class::Reason::QUEUE_FULL,
        event_type: "snapshot")
    end

    it "emits the dropped and dropped_bytes metrics when bytes is provided" do
      telemetry = instance_double(Datadog::Core::Telemetry::Component)
      expect_guardrails_metric(telemetry, name: "guardrails.events.dropped", value: 1,
        tags: {reason: "payloadTooLarge", event_type: "snapshot"})
      expect_guardrails_metric(telemetry, name: "guardrails.queue.dropped_bytes", value: 2048,
        tags: {reason: "payloadTooLarge", event_type: "snapshot"})

      described_class.dropped(telemetry, reason: described_class::Reason::PAYLOAD_TOO_LARGE,
        event_type: "snapshot", bytes: 2048)
    end
  end
end
