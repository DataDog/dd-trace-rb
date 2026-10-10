require "datadog/di/spec_helper"
require "datadog/di/guardrails_telemetry"
require "datadog/di/probe"

RSpec.describe Datadog::DI::GuardrailsTelemetry do
  di_test

  let(:propagate_all_exceptions) { false }

  mock_settings_for_di do |settings|
    allow(settings.dynamic_instrumentation.internal).to receive(:propagate_all_exceptions)
      .and_return(propagate_all_exceptions)
  end

  di_logger_double

  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component).as_null_object }

  let(:guardrails_telemetry) do
    described_class.new(settings: settings, logger: logger, telemetry: telemetry)
  end

  let(:probe) do
    Datadog::DI::Probe.new(id: "p1", type: :log, type_name: "C",
      method_name: "m", capture_snapshot: true,)
  end

  describe ".probe_event_type_tag" do
    it "returns snapshot for a snapshot probe" do
      expect(described_class.probe_event_type_tag(probe)).to eq("snapshot")
    end

    context "for a log probe" do
      let(:probe) do
        Datadog::DI::Probe.new(id: "p1", type: :log, type_name: "C",
          method_name: "m", capture_snapshot: false,)
      end

      it "returns log" do
        expect(described_class.probe_event_type_tag(probe)).to eq("log")
      end
    end
  end

  describe "#skipped" do
    it "emits the canonical skipped metric with reason and event_type tags" do
      expect(telemetry).to receive(:inc).with("debugger", "events.skipped", 1,
        tags: {reason: "rateLimitProbe", event_type: "snapshot"},)

      guardrails_telemetry.skipped(
        reason: described_class::Reason::RATE_LIMIT_PROBE,
        probe: probe,
      )
    end

    it "emits the probe_id tag for a probe-scoped skip" do
      expect(telemetry).to receive(:inc).with("debugger", "events.skipped", 1,
        tags: {reason: "rateLimitProbe", event_type: "snapshot", probe_id: "p1"},)

      guardrails_telemetry.skipped(
        reason: described_class::Reason::RATE_LIMIT_PROBE,
        probe: probe,
        probe_id: probe.id,
      )
    end

    it "reuses a single frozen tag hash for a reason and event_type pair" do
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
      expect(emitted_tags.first).to equal(emitted_tags.last)
      expect(emitted_tags.first).to be_frozen
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
          probe_id: probe.id,
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
          probe_id: probe.id,
        )).to be_nil
      end
    end

    context "when the emission raises" do
      let(:telemetry) { telemetry_double_raising_on_inc }

      it "logs and reports the failure and returns nil" do
        expect_lazy_log(logger, :debug,
          /error emitting debugger\.events\.skipped metric.*StandardError.*telemetry down/)
        expect(telemetry).to receive(:report).with(instance_of(StandardError),
          description: "Error emitting debugger.events.skipped metric")

        expect do
          guardrails_telemetry.skipped(
            reason: described_class::Reason::RATE_LIMIT_PROBE,
            probe: probe,
          )
        end.not_to raise_error
      end
    end

    context "when the emission raises and all exceptions propagate" do
      let(:propagate_all_exceptions) { true }
      let(:telemetry) { telemetry_double_raising_on_inc }

      it "raises the telemetry failure" do
        expect do
          guardrails_telemetry.skipped(
            reason: described_class::Reason::RATE_LIMIT_PROBE,
            probe: probe,
          )
        end.to raise_error(StandardError, "telemetry down")
      end
    end

    context "when the emission raises a fatal exception" do
      let(:telemetry) { telemetry_double_raising_on_inc(exception: SystemExit) }

      it "re-raises the fatal exception" do
        expect do
          guardrails_telemetry.skipped(
            reason: described_class::Reason::RATE_LIMIT_PROBE,
            probe: probe,
          )
        end.to raise_error(SystemExit)
      end
    end
  end

  describe "#dropped" do
    it "emits only the dropped metric when bytes is omitted" do
      expect(telemetry).to receive(:inc).with("debugger", "events.dropped", 1,
        tags: {reason: "queueFull", event_type: "snapshot"},)

      guardrails_telemetry.dropped(
        reason: described_class::Reason::QUEUE_FULL,
        event_type: "snapshot",
      )
    end

    it "emits the dropped and dropped_bytes metrics when bytes is provided" do
      expect(telemetry).to receive(:inc).with("debugger", "events.dropped", 1,
        tags: {reason: "payloadTooLarge", event_type: "snapshot"},)
      expect(telemetry).to receive(:inc).with("dynamic_instrumentation", "guardrails.queue.dropped_bytes", 2048,
        tags: {reason: "payloadTooLarge", event_type: "snapshot"},)

      guardrails_telemetry.dropped(
        reason: described_class::Reason::PAYLOAD_TOO_LARGE,
        event_type: "snapshot", bytes: 2048,
      )
    end

    it "reuses a single frozen tag hash for a reason and event_type pair" do
      emitted_tags = []
      allow(telemetry).to receive(:inc) do |_namespace, _name, _value, tags:|
        emitted_tags << tags
      end

      2.times do
        guardrails_telemetry.dropped(
          reason: described_class::Reason::QUEUE_FULL,
          event_type: "snapshot",
        )
      end

      expect(emitted_tags.length).to eq(2)
      expect(emitted_tags.first).to equal(emitted_tags.last)
      expect(emitted_tags.first).to be_frozen
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

      it "logs and reports the failure and returns nil" do
        expect_lazy_log(logger, :debug,
          /error emitting debugger\.events\.dropped metric.*StandardError.*telemetry down/)
        expect(telemetry).to receive(:report).with(instance_of(StandardError),
          description: "Error emitting debugger.events.dropped metric")

        expect do
          guardrails_telemetry.dropped(
            reason: described_class::Reason::QUEUE_FULL,
            event_type: "snapshot",
          )
        end.not_to raise_error
      end
    end
  end

  describe "#capture_incomplete" do
    it "emits the canonical capture-incomplete metric with reason and event_type tags" do
      expect(telemetry).to receive(:inc).with("debugger", "capture.incomplete", 1,
        tags: {reason: "depth", event_type: "snapshot"},)

      guardrails_telemetry.capture_incomplete(
        reason: described_class::Reason::DEPTH,
        event_type: "snapshot",
      )
    end

    it "reuses a single frozen tag hash for a reason and event_type pair" do
      emitted_tags = []
      allow(telemetry).to receive(:inc) do |_namespace, _name, _value, tags:|
        emitted_tags << tags
      end

      2.times do
        guardrails_telemetry.capture_incomplete(
          reason: described_class::Reason::DEPTH,
          event_type: "snapshot",
        )
      end

      expect(emitted_tags.length).to eq(2)
      expect(emitted_tags.first).to equal(emitted_tags.last)
      expect(emitted_tags.first).to be_frozen
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

      it "logs and reports the failure and returns nil" do
        expect_lazy_log(logger, :debug,
          /error emitting debugger\.capture\.incomplete metric.*StandardError.*telemetry down/)
        expect(telemetry).to receive(:report).with(instance_of(StandardError),
          description: "Error emitting debugger.capture.incomplete metric")

        expect do
          guardrails_telemetry.capture_incomplete(
            reason: described_class::Reason::DEPTH,
            event_type: "snapshot",
          )
        end.not_to raise_error
      end
    end
  end
end
