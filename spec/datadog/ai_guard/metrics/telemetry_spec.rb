# frozen_string_literal: true

require "datadog/ai_guard"
require "datadog/ai_guard/component"
require "datadog/core/telemetry/component"

RSpec.describe Datadog::AIGuard::Metrics::Telemetry do
  before { allow(Datadog::AIGuard).to receive(:telemetry).and_return(telemetry) }

  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }

  describe ".report_evaluation" do
    context "when redaction is performed and applies a replacement" do
      let(:outcome) do
        instance_double(
          Datadog::AIGuard::Evaluation::Outcome,
          result: result,
          redaction: redaction
        )
      end
      let(:result) { instance_double(Datadog::AIGuard::Evaluation::Result, action: "ALLOW") }
      let(:redaction) do
        instance_double(
          Datadog::AIGuard::Redaction::Result,
          performed?: true,
          redacted?: true,
          failures: 0
        )
      end

      it "reports the evaluation as redacted" do
        expect(telemetry).to receive(:inc).with(
          "ai_guard",
          "requests",
          1,
          tags: {action: "ALLOW", block: "false", error: "false", redacted: "true"}
        )

        described_class.report_evaluation(outcome, blocked: false)
      end
    end

    context "when redaction is performed without applying a replacement" do
      let(:outcome) do
        instance_double(
          Datadog::AIGuard::Evaluation::Outcome,
          result: result,
          redaction: redaction
        )
      end
      let(:result) { instance_double(Datadog::AIGuard::Evaluation::Result, action: "ALLOW") }
      let(:redaction) do
        instance_double(
          Datadog::AIGuard::Redaction::Result,
          performed?: true,
          redacted?: false,
          failures: 0
        )
      end

      it "reports the evaluation as not redacted" do
        expect(telemetry).to receive(:inc).with(
          "ai_guard",
          "requests",
          1,
          tags: {action: "ALLOW", block: "false", error: "false", redacted: "false"}
        )

        described_class.report_evaluation(outcome, blocked: false)
      end
    end

    context "when redaction is skipped" do
      let(:outcome) do
        instance_double(
          Datadog::AIGuard::Evaluation::Outcome,
          result: result,
          redaction: redaction
        )
      end
      let(:result) { instance_double(Datadog::AIGuard::Evaluation::Result, action: "ALLOW") }
      let(:redaction) do
        instance_double(
          Datadog::AIGuard::Redaction::Result,
          performed?: false,
          failures: 0
        )
      end

      it "omits the redacted tag" do
        expect(telemetry).to receive(:inc).with(
          "ai_guard",
          "requests",
          1,
          tags: {action: "ALLOW", block: "false", error: "false"}
        )

        described_class.report_evaluation(outcome, blocked: false)
      end
    end

    context "when the evaluation actually blocks" do
      let(:outcome) do
        instance_double(
          Datadog::AIGuard::Evaluation::Outcome,
          result: result,
          redaction: redaction
        )
      end
      let(:result) { instance_double(Datadog::AIGuard::Evaluation::Result, action: "DENY") }
      let(:redaction) do
        instance_double(
          Datadog::AIGuard::Redaction::Result,
          performed?: true,
          redacted?: true,
          failures: 0
        )
      end

      it "reports block as true" do
        expect(telemetry).to receive(:inc).with(
          "ai_guard",
          "requests",
          1,
          tags: {action: "DENY", block: "true", error: "false", redacted: "true"}
        )

        described_class.report_evaluation(outcome, blocked: true)
      end
    end

    context "when blocking is recommended but does not happen" do
      let(:outcome) do
        instance_double(
          Datadog::AIGuard::Evaluation::Outcome,
          result: result,
          redaction: redaction
        )
      end
      let(:result) { instance_double(Datadog::AIGuard::Evaluation::Result, action: "DENY") }
      let(:redaction) do
        instance_double(
          Datadog::AIGuard::Redaction::Result,
          performed?: true,
          redacted?: false,
          failures: 0
        )
      end

      it "reports block as false" do
        expect(telemetry).to receive(:inc).with(
          "ai_guard",
          "requests",
          1,
          tags: {action: "DENY", block: "false", error: "false", redacted: "false"}
        )

        described_class.report_evaluation(outcome, blocked: false)
      end
    end

    context "when replacement failures are recorded" do
      let(:outcome) do
        instance_double(
          Datadog::AIGuard::Evaluation::Outcome,
          result: result,
          redaction: redaction
        )
      end
      let(:result) { instance_double(Datadog::AIGuard::Evaluation::Result, action: "ALLOW") }
      let(:redaction) do
        instance_double(
          Datadog::AIGuard::Redaction::Result,
          performed?: true,
          redacted?: false,
          failures: 3
        )
      end

      it "reports every redaction failure" do
        expect(telemetry).to receive(:inc).with(
          "ai_guard",
          "requests",
          1,
          tags: {action: "ALLOW", block: "false", error: "false", redacted: "false"}
        )
        expect(telemetry).to receive(:inc).with(
          "ai_guard",
          "error",
          3,
          tags: {type: "redaction_error"}
        )

        described_class.report_evaluation(outcome, blocked: false)
      end
    end

    context "when telemetry is unavailable" do
      before { allow(Datadog::AIGuard).to receive(:telemetry).and_return(nil) }

      let(:outcome) { instance_double(Datadog::AIGuard::Evaluation::Outcome) }

      it { expect(described_class.report_evaluation(outcome, blocked: false)).to be_nil }
    end
  end

  describe ".report_error" do
    context "when telemetry is available" do
      it "reports the failed request and client error" do
        expect(telemetry).to receive(:inc).with(
          "ai_guard",
          "requests",
          1,
          tags: {error: "true"}
        )
        expect(telemetry).to receive(:inc).with(
          "ai_guard",
          "error",
          1,
          tags: {type: "client_error"}
        )

        described_class.report_error
      end
    end

    context "when telemetry is unavailable" do
      before { allow(Datadog::AIGuard).to receive(:telemetry).and_return(nil) }

      it { expect(described_class.report_error).to be_nil }
    end
  end
end
