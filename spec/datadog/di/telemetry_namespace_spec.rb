require "datadog/di/spec_helper"
require "open3"

RSpec.describe "DI telemetry namespace under direct requires" do
  di_test

  # Each child process starts with no Datadog code loaded, reproducing the
  # direct-require chains through which the emitter files are reached; this
  # process already has Datadog loaded, so a constant missing from those
  # chains would stay hidden in an in-process example.
  def run_direct_require_script(script)
    out, status = Open3.capture2e("ruby", stdin_data: script)
    unless status.exitstatus == 0
      fail("Direct-require script failed with exit status #{status.exitstatus}:\n#{out}")
    end
    out
  end

  # rubocop:disable Lint/ConstantDefinitionInBlock
  EMIT_SKIP_SCRIPT = <<~'SCRIPT'
    require "datadog/di/guardrails_telemetry"

    telemetry = Object.new

    def telemetry.inc(namespace, metric_name, value, tags: {}, common: true)
      raise "wrong telemetry namespace: #{namespace}" unless namespace == "debugger"
      raise "wrong metric name: #{metric_name}" unless metric_name == "events.skipped"

      nil
    end

    probe = Object.new

    def probe.capture_snapshot?
      true
    end

    Datadog::DI::GuardrailsTelemetry.new(settings: Object.new, logger: Object.new, telemetry: telemetry).skipped(
      reason: Datadog::DI::GuardrailsTelemetry::Reason::RATE_LIMIT_PROBE,
      probe: probe,
    )
  SCRIPT

  EVALUATOR_SCRIPT = <<~SCRIPT
    require "datadog/di/capture_expression_evaluator"

    puts Datadog::DI::TELEMETRY_NAMESPACE
  SCRIPT

  DI_ENTRY_SCRIPT = <<~SCRIPT
    require "datadog/di"

    puts Datadog::DI::TELEMETRY_NAMESPACE
  SCRIPT

  SERIALIZER_SCRIPT = <<~'SCRIPT'
    require "datadog/di/serializer"

    telemetry = Object.new

    def telemetry.inc(namespace, metric_name, value, tags: {}, common: true)
      raise "wrong telemetry namespace: #{namespace}" unless namespace == "debugger"
      raise "wrong metric name: #{metric_name}" unless metric_name == "capture.incomplete"
      raise "wrong reason: #{tags[:reason]}" unless tags[:reason] == "depth"
      raise "wrong event type: #{tags[:event_type]}" unless tags[:event_type] == "snapshot"

      nil
    end

    guardrails_telemetry = Datadog::DI::GuardrailsTelemetry.new(
      settings: Object.new, logger: Object.new, telemetry: telemetry,
    )

    settings = Object.new

    def settings.dynamic_instrumentation
      di_settings = Object.new

      def di_settings.max_capture_attribute_count
        100
      end

      di_settings
    end

    redactor = Object.new

    def redactor.redact_type?(value)
      false
    end

    def redactor.redact_identifier?(name)
      false
    end

    Datadog::DI::Serializer.new(settings, redactor,
      guardrails_telemetry: guardrails_telemetry).serialize_value([1], depth: 0)
  SCRIPT
  # rubocop:enable Lint/ConstantDefinitionInBlock

  it "emits the guardrails skip metric under the debugger namespace when guardrails telemetry is required directly" do
    expect(run_direct_require_script(EMIT_SKIP_SCRIPT)).to be_empty
  end

  it "resolves the namespace when the capture expression evaluator is required directly" do
    expect(run_direct_require_script(EVALUATOR_SCRIPT)).to eq("dynamic_instrumentation\n")
  end

  it "resolves the namespace when datadog/di is required directly" do
    expect(run_direct_require_script(DI_ENTRY_SCRIPT)).to eq("dynamic_instrumentation\n")
  end

  it "emits the capture-incomplete metric when the serializer is required directly" do
    expect(run_direct_require_script(SERIALIZER_SCRIPT)).to be_empty
  end
end
