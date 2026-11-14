require "datadog/di/spec_helper"
require "datadog/di/guardrails_telemetry"
require "datadog/di/probe"

RSpec.describe Datadog::DI::GuardrailsTelemetry do
  di_test

  di_logger_double

  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component).as_null_object }

  let(:guardrails_telemetry) do
    described_class.new(logger: logger, telemetry: telemetry)
  end

  let(:probe) do
    Datadog::DI::Probe.new(id: "p1", type: :log, type_name: "C",
      method_name: "m", capture_snapshot: true)
  end

  # Emits the given emission twice and asserts both emissions reuse one
  # frozen tag hash.
  def expect_reused_frozen_tags(&emission)
    emitted_tags = []
    allow(telemetry).to receive(:inc) do |_namespace, _name, _value, tags:|
      emitted_tags << tags
    end

    2.times(&emission)

    expect(emitted_tags.length).to eq(2)
    expect(emitted_tags.first).to equal(emitted_tags.last)
    expect(emitted_tags.first).to be_frozen
  end

  describe ".probe_event_type_tag" do
    it "returns snapshot for a snapshot probe" do
      expect(described_class.probe_event_type_tag(probe)).to eq("snapshot")
    end

    context "for a log probe" do
      let(:probe) do
        Datadog::DI::Probe.new(id: "p1", type: :log, type_name: "C",
          method_name: "m", capture_snapshot: false)
      end

      it "returns log" do
        expect(described_class.probe_event_type_tag(probe)).to eq("log")
      end
    end
  end

  describe "#skipped" do
    it "emits the canonical skipped metric with the probe id tag for a probe-scoped reason" do
      expect(telemetry).to receive(:inc).with("debugger", "events.skipped", 1,
        tags: {reason: "rateLimitProbe", event_type: "snapshot", probe_id: "p1"})

      guardrails_telemetry.skipped(
        reason: described_class::Reason::RATE_LIMIT_PROBE,
        probe: probe,
      )
    end

    it "omits the probe id tag for a process-scoped reason" do
      expect(telemetry).to receive(:inc).with("debugger", "events.skipped", 1,
        tags: {reason: "rateLimitGlobal", event_type: "snapshot"})

      guardrails_telemetry.skipped(
        reason: described_class::Reason::RATE_LIMIT_GLOBAL,
        probe: probe,
      )
    end

    it "reuses a single frozen tag hash for a process-scoped reason" do
      expect_reused_frozen_tags do
        guardrails_telemetry.skipped(
          reason: described_class::Reason::RATE_LIMIT_GLOBAL,
          probe: probe,
        )
      end
    end

    it "emits a frozen tag hash per probe-scoped skip" do
      emitted_tags = []
      allow(telemetry).to receive(:inc) do |_namespace, _name, _value, tags:|
        emitted_tags << tags
      end

      2.times do
        guardrails_telemetry.skipped(
          reason: described_class::Reason::RATE_LIMIT_PROBE,
          probe: probe,
        )
      end

      expect(emitted_tags.length).to eq(2)
      expect(emitted_tags.first).not_to equal(emitted_tags.last)
      expect(emitted_tags.first).to be_frozen
      expect(emitted_tags.last).to be_frozen
    end

    context "when telemetry is nil" do
      let(:telemetry) { nil }

      it "emits no metric and returns nil" do
        expect(guardrails_telemetry.skipped(
          reason: described_class::Reason::RATE_LIMIT_PROBE,
          probe: probe,
        )).to be_nil
      end
    end

    context "when the emission raises" do
      let(:telemetry) { telemetry_double_raising_on_inc }

      it "propagates the telemetry failure" do
        expect do
          guardrails_telemetry.skipped(
            reason: described_class::Reason::RATE_LIMIT_PROBE,
            probe: probe,
          )
        end.to raise_error(StandardError, "telemetry down")
      end
    end
  end

  describe "#dropped" do
    it "emits only the dropped metric when bytes is omitted" do
      expect(telemetry).to receive(:inc).with("debugger", "events.dropped", 1,
        tags: {reason: "queueFull", event_type: "snapshot"})

      guardrails_telemetry.dropped(
        reason: described_class::Reason::QUEUE_FULL,
        event_type: "snapshot",
      )
    end

    it "emits the dropped and dropped_bytes metrics when bytes is provided" do
      expect(telemetry).to receive(:inc).with("debugger", "events.dropped", 1,
        tags: {reason: "payloadTooLarge", event_type: "snapshot"})
      expect(telemetry).to receive(:inc).with("debugger", "guardrails.queue.dropped_bytes", 2048,
        tags: {reason: "payloadTooLarge", event_type: "snapshot"})

      guardrails_telemetry.dropped(
        reason: described_class::Reason::PAYLOAD_TOO_LARGE,
        event_type: "snapshot", bytes: 2048,
      )
    end

    it "reuses a single frozen tag hash for a reason and event_type pair" do
      expect_reused_frozen_tags do
        guardrails_telemetry.dropped(
          reason: described_class::Reason::QUEUE_FULL,
          event_type: "snapshot",
        )
      end
    end

    context "when telemetry is nil" do
      let(:telemetry) { nil }

      it "emits no metric and returns nil" do
        expect(guardrails_telemetry.dropped(
          reason: described_class::Reason::QUEUE_FULL,
          event_type: "snapshot", bytes: 2048,
        )).to be_nil
      end
    end

    context "when the emission raises" do
      let(:telemetry) { telemetry_double_raising_on_inc }

      it "propagates the telemetry failure" do
        expect do
          guardrails_telemetry.dropped(
            reason: described_class::Reason::QUEUE_FULL,
            event_type: "snapshot",
          )
        end.to raise_error(StandardError, "telemetry down")
      end
    end
  end

  describe "#capture_incomplete" do
    it "emits the canonical capture-incomplete metric with reason and event_type tags" do
      expect(telemetry).to receive(:inc).with("debugger", "capture.incomplete", 1,
        tags: {reason: "depth", event_type: "snapshot"})

      guardrails_telemetry.capture_incomplete(
        reason: described_class::Reason::DEPTH,
        event_type: "snapshot",
      )
    end

    it "reuses a single frozen tag hash for a reason and event_type pair" do
      expect_reused_frozen_tags do
        guardrails_telemetry.capture_incomplete(
          reason: described_class::Reason::DEPTH,
          event_type: "snapshot",
        )
      end
    end

    context "when telemetry is nil" do
      let(:telemetry) { nil }

      it "emits no metric and returns nil" do
        expect(guardrails_telemetry.capture_incomplete(
          reason: described_class::Reason::DEPTH,
          event_type: "snapshot",
        )).to be_nil
      end
    end

    context "when the emission raises" do
      let(:telemetry) { telemetry_double_raising_on_inc }

      it "propagates the telemetry failure" do
        expect do
          guardrails_telemetry.capture_incomplete(
            reason: described_class::Reason::DEPTH,
            event_type: "snapshot",
          )
        end.to raise_error(StandardError, "telemetry down")
      end
    end
  end
end
