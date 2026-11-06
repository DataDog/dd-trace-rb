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

  let(:metrics_enabled) { true }

  let(:telemetry) do
    instance_double(Datadog::Core::Telemetry::Component,
      metrics_manager: instance_double(Datadog::Core::Telemetry::MetricsManager, enabled: metrics_enabled),
      report: nil)
  end

  let(:guardrails_telemetry) do
    described_class.new(settings: settings, logger: logger, telemetry: telemetry)
  end

  # A plain object holding a real enabled metrics manager: dispatching a
  # message to an RSpec double allocates, which would hide the
  # allocations of the recorder itself.
  let(:allocation_free_telemetry) do
    Struct.new(:metrics_manager).new(
      Datadog::Core::Telemetry::MetricsManager.new(aggregation_interval: 10, enabled: true),
    )
  end

  let(:probe) do
    Datadog::DI::Probe.new(id: "p1", type: :log, type_name: "C",
      method_name: "m", capture_snapshot: true)
  end

  let(:log_probe) do
    Datadog::DI::Probe.new(id: "p2", type: :log, type_name: "C",
      method_name: "m", capture_snapshot: false)
  end

  before do
    allow(logger).to receive(:debug)
  end

  def record_one_of_each
    guardrails_telemetry.skipped(reason: described_class::Reason::RATE_LIMIT_PROBE, probe: probe)
    guardrails_telemetry.dropped(reason: described_class::Reason::PAYLOAD_TOO_LARGE, event_type: "log", bytes: 10)
    guardrails_telemetry.capture_incomplete(reason: described_class::Reason::DEPTH, event_type: "snapshot")
  end

  describe ".probe_event_type_tag" do
    it "returns snapshot for a snapshot probe" do
      expect(described_class.probe_event_type_tag(probe)).to eq("snapshot")
    end

    it "returns log for a log probe" do
      expect(described_class.probe_event_type_tag(log_probe)).to eq("log")
    end
  end

  describe "#counting?" do
    it "is true when the telemetry metrics manager is enabled" do
      expect(guardrails_telemetry.counting?).to be true
    end

    context "when the telemetry metrics manager is disabled" do
      let(:metrics_enabled) { false }

      it "is false" do
        expect(guardrails_telemetry.counting?).to be false
      end
    end

    context "when telemetry is nil" do
      let(:telemetry) { nil }

      it "is false" do
        expect(guardrails_telemetry.counting?).to be false
      end
    end
  end

  describe "#skipped" do
    it "counts a probe-scoped reason per probe id" do
      2.times { guardrails_telemetry.skipped(reason: described_class::Reason::RATE_LIMIT_PROBE, probe: probe) }
      guardrails_telemetry.skipped(reason: described_class::Reason::RATE_LIMIT_PROBE, probe: log_probe)

      expect(reported_guardrail_metrics(guardrails_telemetry)).to contain_exactly(
        ["debugger", "events.skipped", 2, {reason: "rateLimitProbe", event_type: "snapshot", probe_id: "p1"}],
        ["debugger", "events.skipped", 1, {reason: "rateLimitProbe", event_type: "log", probe_id: "p2"}],
      )
    end

    it "counts a process-scoped reason without the probe id" do
      guardrails_telemetry.skipped(reason: described_class::Reason::RATE_LIMIT_GLOBAL, probe: probe)
      guardrails_telemetry.skipped(reason: described_class::Reason::RATE_LIMIT_GLOBAL, probe: log_probe)
      guardrails_telemetry.skipped(reason: described_class::Reason::RATE_LIMIT_GLOBAL, probe: probe)

      expect(reported_guardrail_metrics(guardrails_telemetry)).to contain_exactly(
        ["debugger", "events.skipped", 2, {reason: "rateLimitGlobal", event_type: "snapshot"}],
        ["debugger", "events.skipped", 1, {reason: "rateLimitGlobal", event_type: "log"}],
      )
    end

    it "returns nil" do
      expect(guardrails_telemetry.skipped(reason: described_class::Reason::RATE_LIMIT_PROBE, probe: probe)).to be_nil
    end

    context "with a real metrics manager" do
      let(:telemetry) { allocation_free_telemetry }

      it "allocates no object when the count already exists" do
        guardrails_telemetry.skipped(reason: described_class::Reason::RATE_LIMIT_PROBE, probe: probe)
        guardrails_telemetry.skipped(reason: described_class::Reason::RATE_LIMIT_GLOBAL, probe: probe)

        recorder = guardrails_telemetry
        probe_scoped = described_class::Reason::RATE_LIMIT_PROBE
        process_scoped = described_class::Reason::RATE_LIMIT_GLOBAL
        skipped_probe = probe
        allocations = allocations_per_call do
          recorder.skipped(reason: probe_scoped, probe: skipped_probe)
          recorder.skipped(reason: process_scoped, probe: skipped_probe)
        end

        expect(allocations).to be < 1
      end
    end

    it "sums the occurrences recorded from several threads" do
      threads = Array.new(4) do
        Thread.new do
          250.times { guardrails_telemetry.skipped(reason: described_class::Reason::RATE_LIMIT_PROBE, probe: probe) }
        end
      end
      threads.each(&:join)

      expect(reported_guardrail_metrics(guardrails_telemetry)).to eq(
        [["debugger", "events.skipped", 1000, {reason: "rateLimitProbe", event_type: "snapshot", probe_id: "p1"}]],
      )
    end

    context "when the telemetry metrics manager is disabled" do
      let(:metrics_enabled) { false }

      it "counts nothing" do
        guardrails_telemetry.skipped(reason: described_class::Reason::RATE_LIMIT_PROBE, probe: probe)

        expect(guardrails_telemetry.skipped_counts).to eq({})
      end
    end

    context "when telemetry is nil" do
      let(:telemetry) { nil }

      it "counts nothing and returns nil" do
        expect(guardrails_telemetry.skipped(reason: described_class::Reason::RATE_LIMIT_PROBE, probe: probe)).to be_nil
        expect(guardrails_telemetry.skipped_counts).to eq({})
      end
    end
  end

  describe "#dropped" do
    it "counts the drop without a byte total when bytes is omitted" do
      2.times { guardrails_telemetry.dropped(reason: described_class::Reason::QUEUE_FULL, event_type: "snapshot") }

      expect(reported_guardrail_metrics(guardrails_telemetry)).to eq(
        [["debugger", "events.dropped", 2, {reason: "queueFull", event_type: "snapshot"}]],
      )
    end

    it "counts the drop and sums the discarded bytes when bytes is provided" do
      guardrails_telemetry.dropped(reason: described_class::Reason::PAYLOAD_TOO_LARGE, event_type: "snapshot", bytes: 2048)
      guardrails_telemetry.dropped(reason: described_class::Reason::PAYLOAD_TOO_LARGE, event_type: "snapshot", bytes: 100)

      expect(reported_guardrail_metrics(guardrails_telemetry)).to contain_exactly(
        ["debugger", "events.dropped", 2, {reason: "payloadTooLarge", event_type: "snapshot"}],
        ["debugger", "guardrails.queue.dropped_bytes", 2148, {reason: "payloadTooLarge", event_type: "snapshot"}],
      )
    end

    context "with a real metrics manager" do
      let(:telemetry) { allocation_free_telemetry }

      it "allocates no object when the counts already exist" do
        guardrails_telemetry.dropped(reason: described_class::Reason::PAYLOAD_TOO_LARGE, event_type: "snapshot", bytes: 1)

        recorder = guardrails_telemetry
        reason = described_class::Reason::PAYLOAD_TOO_LARGE
        event_type = described_class::EVENT_TYPE_SNAPSHOT
        allocations = allocations_per_call do
          recorder.dropped(reason: reason, event_type: event_type, bytes: 1)
        end

        expect(allocations).to be < 1
      end
    end

    context "when telemetry is nil" do
      let(:telemetry) { nil }

      it "counts nothing and returns nil" do
        expect(guardrails_telemetry.dropped(reason: described_class::Reason::QUEUE_FULL,
          event_type: "snapshot", bytes: 2048)).to be_nil
        expect(guardrails_telemetry.dropped_counts).to eq({})
        expect(guardrails_telemetry.dropped_bytes).to eq({})
      end
    end
  end

  describe "#capture_incomplete" do
    it "counts the enforced capture limit per reason and event type" do
      2.times { guardrails_telemetry.capture_incomplete(reason: described_class::Reason::DEPTH, event_type: "snapshot") }
      guardrails_telemetry.capture_incomplete(reason: described_class::Reason::DEPTH, event_type: "log")

      expect(reported_guardrail_metrics(guardrails_telemetry)).to contain_exactly(
        ["debugger", "capture.incomplete", 2, {reason: "depth", event_type: "snapshot"}],
        ["debugger", "capture.incomplete", 1, {reason: "depth", event_type: "log"}],
      )
    end

    context "with a real metrics manager" do
      let(:telemetry) { allocation_free_telemetry }

      it "allocates no object when the count already exists" do
        guardrails_telemetry.capture_incomplete(reason: described_class::Reason::DEPTH, event_type: "snapshot")

        recorder = guardrails_telemetry
        reason = described_class::Reason::DEPTH
        event_type = described_class::EVENT_TYPE_SNAPSHOT
        allocations = allocations_per_call do
          recorder.capture_incomplete(reason: reason, event_type: event_type)
        end

        expect(allocations).to be < 1
      end
    end

    context "when telemetry is nil" do
      let(:telemetry) { nil }

      it "counts nothing and returns nil" do
        expect(guardrails_telemetry.capture_incomplete(reason: described_class::Reason::DEPTH,
          event_type: "snapshot")).to be_nil
        expect(guardrails_telemetry.capture_incomplete_counts).to eq({})
      end
    end
  end

  describe "#report_metrics" do
    it "records every metric kind and returns nil" do
      record_one_of_each
      metrics_manager = instance_double(Datadog::Core::Telemetry::MetricsManager)
      expect(metrics_manager).to receive(:inc).with("debugger", "events.skipped", 1,
        tags: {reason: "rateLimitProbe", event_type: "snapshot", probe_id: "p1"})
      expect(metrics_manager).to receive(:inc).with("debugger", "events.dropped", 1,
        tags: {reason: "payloadTooLarge", event_type: "log"})
      expect(metrics_manager).to receive(:inc).with("debugger", "guardrails.queue.dropped_bytes", 10,
        tags: {reason: "payloadTooLarge", event_type: "log"})
      expect(metrics_manager).to receive(:inc).with("debugger", "capture.incomplete", 1,
        tags: {reason: "depth", event_type: "snapshot"})

      expect(guardrails_telemetry.report_metrics(metrics_manager)).to be_nil
    end

    it "empties the count tables" do
      record_one_of_each
      reported_guardrail_metrics(guardrails_telemetry)

      expect(guardrails_telemetry.skipped_counts).to eq({})
      expect(guardrails_telemetry.dropped_counts).to eq({})
      expect(guardrails_telemetry.dropped_bytes).to eq({})
      expect(guardrails_telemetry.capture_incomplete_counts).to eq({})
      expect(reported_guardrail_metrics(guardrails_telemetry)).to eq([])
    end

    it "logs the number of reported series" do
      record_one_of_each
      expect_lazy_log(logger, :debug, "di: reported 4 guardrail metric series")

      guardrails_telemetry.report_metrics(instance_double(Datadog::Core::Telemetry::MetricsManager, inc: nil))
    end

    it "logs nothing when there is nothing to report" do
      expect(logger).not_to receive(:debug)

      guardrails_telemetry.report_metrics(instance_double(Datadog::Core::Telemetry::MetricsManager))
    end

    it "sets last_reported_at to the report time" do
      report_time = Time.at(1_700_000_000)
      allow(Datadog::Core::Utils::Time).to receive(:now).and_return(report_time)

      expect(guardrails_telemetry.last_reported_at).to be_nil
      reported_guardrail_metrics(guardrails_telemetry)
      expect(guardrails_telemetry.last_reported_at).to eq(report_time)
    end

    context "when a record fails" do
      let(:metrics_manager) { metrics_manager_double_raising_on_inc }

      it "logs and reports every failure and attempts every series" do
        record_one_of_each
        expect(logger).to receive(:debug).exactly(5).times
        expect(telemetry).to receive(:report).with(instance_of(StandardError),
          description: "Error emitting debugger.events.skipped metric")
        expect(telemetry).to receive(:report).with(instance_of(StandardError),
          description: "Error emitting debugger.events.dropped metric")
        expect(telemetry).to receive(:report).with(instance_of(StandardError),
          description: "Error emitting debugger.guardrails.queue.dropped_bytes metric")
        expect(telemetry).to receive(:report).with(instance_of(StandardError),
          description: "Error emitting debugger.capture.incomplete metric")

        expect(guardrails_telemetry.report_metrics(metrics_manager)).to be_nil
        expect(metrics_manager).to have_received(:inc).exactly(4).times
      end

      it "logs the failure at debug" do
        guardrails_telemetry.capture_incomplete(reason: described_class::Reason::DEPTH, event_type: "snapshot")
        expect_lazy_log_many(logger, :debug,
          /error emitting debugger\.capture\.incomplete metric.*StandardError.*telemetry down/,
          "di: reported 1 guardrail metric series")

        guardrails_telemetry.report_metrics(metrics_manager)
      end
    end

    context "when reporting the record failure also raises" do
      let(:metrics_manager) { metrics_manager_double_raising_on_inc }

      before do
        allow(telemetry).to receive(:report).and_raise(StandardError.new("report down"))
      end

      it "logs the nested failure and stays contained" do
        guardrails_telemetry.capture_incomplete(reason: described_class::Reason::DEPTH, event_type: "snapshot")
        expect_lazy_log_many(logger, :debug,
          /error emitting debugger\.capture\.incomplete metric.*StandardError.*telemetry down/,
          /error reporting debugger\.capture\.incomplete metric emission failure.*StandardError.*report down/,
          "di: reported 1 guardrail metric series")

        expect { guardrails_telemetry.report_metrics(metrics_manager) }.not_to raise_error
      end
    end

    context "when reporting the record failure raises a fatal exception" do
      let(:metrics_manager) { metrics_manager_double_raising_on_inc }

      before do
        allow(telemetry).to receive(:report).and_raise(SystemExit)
      end

      it "re-raises the fatal nested exception" do
        guardrails_telemetry.capture_incomplete(reason: described_class::Reason::DEPTH, event_type: "snapshot")

        expect { guardrails_telemetry.report_metrics(metrics_manager) }.to raise_error(SystemExit)
      end
    end

    context "when a record fails and all exceptions propagate" do
      let(:propagate_all_exceptions) { true }
      let(:metrics_manager) { metrics_manager_double_raising_on_inc }

      it "raises the failure" do
        guardrails_telemetry.capture_incomplete(reason: described_class::Reason::DEPTH, event_type: "snapshot")

        expect { guardrails_telemetry.report_metrics(metrics_manager) }.to raise_error(StandardError, "telemetry down")
      end
    end

    context "when a record raises a fatal exception" do
      let(:metrics_manager) { metrics_manager_double_raising_on_inc(exception: SystemExit) }

      it "re-raises the fatal exception" do
        guardrails_telemetry.capture_incomplete(reason: described_class::Reason::DEPTH, event_type: "snapshot")

        expect { guardrails_telemetry.report_metrics(metrics_manager) }.to raise_error(SystemExit)
      end
    end
  end

  describe "#clear_metrics" do
    it "discards the counts and returns nil" do
      record_one_of_each

      expect(guardrails_telemetry.clear_metrics).to be_nil
      expect(reported_guardrail_metrics(guardrails_telemetry)).to eq([])
    end
  end

  context "registered with a telemetry metrics manager" do
    let(:metrics_manager) { Datadog::Core::Telemetry::MetricsManager.new(aggregation_interval: 10, enabled: true) }

    let(:telemetry) do
      instance_double(Datadog::Core::Telemetry::Component, metrics_manager: metrics_manager, report: nil)
    end

    before do
      metrics_manager.register_source(guardrails_telemetry)
    end

    it "sends the counts in the metrics manager's next flush" do
      2.times { guardrails_telemetry.skipped(reason: described_class::Reason::RATE_LIMIT_PROBE, probe: probe) }

      series = metrics_manager.flush!.flat_map { |event| event.payload[:series] }

      expect(series).to contain_exactly(
        a_hash_including(metric: "events.skipped", tags: %w[reason:rateLimitProbe event_type:snapshot probe_id:p1],
          points: [[kind_of(Integer), 2]]),
      )
    end
  end
end
