require "datadog/di/spec_helper"
require "datadog/di/guardrails"
require "datadog/di/probe"

RSpec.describe Datadog::DI::Guardrails do
  describe ".probe_type_tag" do
    it "returns snapshot for a capturing probe" do
      probe = Datadog::DI::Probe.new(id: "p1", type: :log, type_name: "C",
        method_name: "m", capture_snapshot: true)
      expect(described_class.probe_type_tag(probe)).to eq("snapshot")
    end

    it "returns log for a non-capturing probe" do
      probe = Datadog::DI::Probe.new(id: "p1", type: :log, type_name: "C",
        method_name: "m", capture_snapshot: false)
      expect(described_class.probe_type_tag(probe)).to eq("log")
    end
  end

  describe ".event_type_tag" do
    it "maps snapshot to snapshot" do
      expect(described_class.event_type_tag(:snapshot)).to eq("snapshot")
    end

    it "maps status to diagnostic" do
      expect(described_class.event_type_tag(:status)).to eq("diagnostic")
    end

    it "falls back to the string form for unknown types" do
      expect(described_class.event_type_tag(:log)).to eq("log")
    end
  end

  describe ".skipped" do
    it "is a no-op when telemetry is nil" do
      expect do
        described_class.skipped(nil, reason: described_class::Reason::RATE_LIMIT_PROBE,
          probe_type: "snapshot")
      end.not_to raise_error
    end

    it "emits the canonical skipped metric with reason and probe_type tags" do
      telemetry = instance_double(Datadog::Core::Telemetry::Component)
      expect(telemetry).to receive(:inc) do |namespace, name, value, tags:, **|
        expect(namespace).to eq("dynamic_instrumentation")
        expect(name).to eq("guardrails.events.skipped")
        expect(value).to eq(1)
        expect(tags).to eq(reason: "rateLimitProbe", probe_type: "snapshot")
      end

      described_class.skipped(telemetry, reason: described_class::Reason::RATE_LIMIT_PROBE,
        probe_type: "snapshot")
    end
  end

  describe ".dropped" do
    it "is a no-op when telemetry is nil" do
      expect do
        described_class.dropped(nil, reason: described_class::Reason::QUEUE_FULL,
          event_type: "snapshot", bytes: 100)
      end.not_to raise_error
    end

    it "emits only the dropped metric when bytes is omitted" do
      telemetry = instance_double(Datadog::Core::Telemetry::Component)
      expect(telemetry).to receive(:inc) do |namespace, name, value, tags:, **|
        expect(namespace).to eq("dynamic_instrumentation")
        expect(name).to eq("guardrails.events.dropped")
        expect(value).to eq(1)
        expect(tags).to eq(reason: "queueFull", event_type: "snapshot")
      end

      described_class.dropped(telemetry, reason: described_class::Reason::QUEUE_FULL,
        event_type: "snapshot")
    end

    it "emits the dropped and dropped_bytes metrics when bytes is provided" do
      telemetry = instance_double(Datadog::Core::Telemetry::Component)
      dropped_count = 0
      allow(telemetry).to receive(:inc) do |namespace, name, value, tags:, **|
        case name
        when "guardrails.events.dropped"
          expect(namespace).to eq("dynamic_instrumentation")
          expect(value).to eq(1)
          expect(tags).to eq(reason: "payloadTooLarge", event_type: "snapshot")
          dropped_count += 1
        when "guardrails.queue.dropped_bytes"
          expect(namespace).to eq("dynamic_instrumentation")
          expect(value).to eq(2048)
          expect(tags).to eq(reason: "payloadTooLarge", event_type: "snapshot")
          dropped_count += 1
        end
      end

      described_class.dropped(telemetry, reason: described_class::Reason::PAYLOAD_TOO_LARGE,
        event_type: "snapshot", bytes: 2048)

      expect(dropped_count).to eq(2)
    end
  end
end
