# frozen_string_literal: true

require "spec_helper"
require "open_feature/sdk"
require "timeout"
require "opentelemetry-metrics-sdk"
require "datadog/open_feature/provider"
require "datadog/open_feature/component"

RSpec.describe "OpenFeature evaluation telemetry opt-out" do
  with_env "DD_FEATURE_FLAGS_EVALUATION_TELEMETRY_PER_SUBJECT_OPT_OUT_ENABLED" => nil

  subject(:provider) do
    Datadog::OpenFeature::Provider.new(enable_evaluation_telemetry_opt_out_parameter: opt_out_enabled)
  end

  let(:opt_out_enabled) { true }

  let(:logger) { logger_allowing_debug }
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component, report: nil, inc: nil) }
  let(:evp_payloads) { [] }
  let(:exposure_payloads) { [] }
  let(:transport) { instance_double(Datadog::OpenFeature::Transport::HTTP) }
  let(:writer) { Datadog::OpenFeature::FlagEvaluation::Writer.new(transport: transport, logger: logger) }
  let(:worker) do
    Datadog::OpenFeature::Exposures::Worker.new(
      settings: Datadog.configuration, transport: transport, telemetry: telemetry, logger: logger,
    )
  end
  let(:reporter) { Datadog::OpenFeature::Exposures::Reporter.new(worker, telemetry: telemetry, logger: logger) }
  let(:engine) { Datadog::OpenFeature::EvaluationEngine.new(reporter, telemetry: telemetry, logger: logger) }
  let(:metrics) { Datadog::OpenFeature::Metrics::FlagEvalMetrics.new(telemetry: telemetry, logger: logger) }
  let(:meter_provider) { OpenTelemetry::SDK::Metrics::MeterProvider.new }
  let(:metric_reader) { OpenTelemetry::SDK::Metrics::Export::InMemoryMetricPullExporter.new }
  let(:span_hook) do
    Datadog::OpenFeature::Hooks::SpanEnrichmentHook.new(
      Datadog::OpenFeature::Hooks::SpanEnrichmentHook::SpanEnrichmentStateStore.new, logger: logger,
    )
  end
  let(:trace) { Datadog::Tracing::TraceOperation.new }
  let(:client) { OpenFeature::SDK::Client.new(provider: provider) }
  let(:api_configuration) { OpenFeature::SDK::Configuration.new }
  let(:application_hook) do
    instance_double(OpenFeature::SDK::Hooks::Hook, before: nil, after: nil, error: nil, finally: nil)
  end
  let(:observe_full_evaluation_data) { false }
  let(:configuration) do
    JSON.generate(
      "createdAt" => "2024-04-17T19:40:53.716Z",
      "environment" => {"name" => "test"},
      "observeFullEvaluationData" => observe_full_evaluation_data,
      "flags" => {
        "flag" => {
          "key" => "flag", "enabled" => true, "variationType" => "STRING",
          "variations" => {"on" => {"key" => "on", "value" => "enabled"}},
          "allocations" => [{
            "key" => "experiment",
            "splits" => [{"variationKey" => "on", "shards" => [], "serialId" => 100}],
            "doLog" => true,
          }],
        },
      },
    )
  end

  before do
    allow(OpenFeature::SDK::API.instance).to receive(:configuration).and_return(api_configuration)
    allow(Datadog.configuration.opentelemetry.metrics).to receive(:enabled).and_return(true)
    meter_provider.add_metric_reader(metric_reader)
    allow(OpenTelemetry).to receive(:meter_provider).and_return(meter_provider)
    allow_any_instance_of(Datadog::OpenFeature::FlagEvaluation::Writer)
      .to receive(:start_background_thread)
    allow(worker).to receive(:start)
    allow(transport).to receive(:send_flag_evaluations) do |payload|
      evp_payloads << payload
      nil
    end
    allow(transport).to receive(:send_exposures) do |payload|
      exposure_payloads << payload
      nil
    end
    allow(Datadog::Tracing).to receive(:active_trace).and_return(trace)
    allow(span_hook).to receive(:capture).and_call_original
    component = instance_double(
      Datadog::OpenFeature::Component,
      engine: engine,
      flag_eval_evp_hook: Datadog::OpenFeature::Hooks::FlagEvalEVPHook.new(writer),
      flag_eval_metrics_hook: Datadog::OpenFeature::Hooks::FlagEvalMetricsHook.new(metrics),
      debug_logging_hook: nil,
      span_enrichment_hook: span_hook,
      wait_for_configuration: Datadog::OpenFeature::Component::CONFIGURATION_READY,
    )
    components = instance_double(Datadog::Core::Configuration::Components, open_feature: component)
    allow(Datadog).to receive(:send).and_call_original
    allow(Datadog).to receive(:send).with(:components).and_return(components)
    allow(Datadog::OpenFeature).to receive(:engine).and_return(engine)
    allow(Datadog::OpenFeature).to receive(:activate_provider).and_return([component, nil])
    engine.reconfigure!(configuration)
  end

  after do
    writer.stop
    worker.stop(true, 0)
    span_hook.shutdown
    metric_reader.shutdown
    api_configuration.set_provider_and_wait(OpenFeature::SDK::Provider::NoOpProvider.new)
  end

  def context(subject, value)
    OpenFeature::SDK::EvaluationContext.new(targeting_key: subject, dd_evaluation_telemetry_opt_out: value)
  end

  def evaluate(subject, value, **options)
    client.fetch_string_details(
      flag_key: "flag", default_value: "fallback", evaluation_context: context(subject, value), **options,
    )
  end

  def signal_counts
    writer.send(:drain_and_flush)
    worker.send(:send_events, *worker.dequeue)
    metric_reader.pull
    {
      evp: evp_payloads.sum { |payload| payload["flagEvaluations"].sum { |event| event["evaluation_count"] } },
      metrics: metric_reader.metric_snapshots.select { |metric| metric.name == "feature_flag.evaluations" }
        .sum { |metric| metric.data_points.sum(&:value) },
      exposures: exposure_payloads.sum { |payload| payload[:exposures].size },
      span_annotations: ["ffe_flags_enc", "ffe_subjects_enc", "ffe_runtime_defaults"]
        .count { |tag| trace.get_tag(tag) },
    }
  end

  def expect_signals(evaluations:, exposures:, annotations: evaluations.positive? ? 2 : 0)
    expect(signal_counts).to eq(
      evp: evaluations, metrics: evaluations, exposures: exposures, span_annotations: annotations,
    )
  end

  it "suppresses evaluation signals and preserves the native assignment and exposure" do
    details = nil
    trace.measure("root") { details = evaluate("opted-out", true) }

    expect(details.value).to eq("enabled")
    expect(details.variant).to eq("on")
    expect(details.reason).to eq("STATIC")
    expect(details.error_code).to be_nil
    expect(telemetry).not_to have_received(:report)
    expect(signal_counts).to eq(evp: 0, metrics: 0, exposures: 1, span_annotations: 0)
  end

  [false, nil, "true", "false", 1, 0, [], {}, [true]].each do |value|
    it "retains evaluation signals for #{value.inspect}" do
      trace.measure("root") { expect(evaluate("subject", value).value).to eq("enabled") }

      expect_signals(evaluations: 1, exposures: 1)
    end
  end

  it "retains evaluation signals when the parameter is missing or misspelled" do
    trace.measure("root") do
      client.fetch_string_value(
        flag_key: "flag", default_value: "fallback",
        evaluation_context: OpenFeature::SDK::EvaluationContext.new(
          targeting_key: "subject", dd_telemetry_opt_out: true, ddEvaluationTelemetryOptOut: true,
        ),
      )
    end

    expect_signals(evaluations: 1, exposures: 1)
  end

  it "retains the result and evaluation signals without an evaluation context" do
    details = nil
    trace.measure("root") { details = client.fetch_string_details(flag_key: "flag", default_value: "fallback") }

    expect(details.value).to eq("enabled")
    expect(details.error_code).to be_nil
    expect_signals(evaluations: 1, exposures: 0, annotations: 1)
  end

  ["false", "true", 0, 1, [], {}].each do |value|
    context "with a non-boolean provider option #{value.inspect}" do
      let(:opt_out_enabled) { value }

      it "rejects the option before evaluating flags" do
        expect { provider }.to raise_error(ArgumentError, /enable_evaluation_telemetry_opt_out_parameter/)
      end
    end
  end

  context "when activation is disabled" do
    let(:opt_out_enabled) { false }

    it "retains evaluation signals for boolean true" do
      trace.measure("root") { evaluate("subject", true) }

      expect_signals(evaluations: 1, exposures: 1)
    end
  end

  context "with default provider options" do
    subject(:provider) { Datadog::OpenFeature::Provider.new }

    it "retains evaluation signals for boolean true" do
      trace.measure("root") { evaluate("subject", true) }

      expect_signals(evaluations: 1, exposures: 1)
    end
  end

  context "with ordinary opt-out attribute targeting" do
    let(:configuration) do
      data = JSON.parse(super())
      flag = data.fetch("flags").fetch("flag")
      flag.fetch("variations")["off"] = {"key" => "off", "value" => "disabled"}
      flag.fetch("allocations").first["rules"] = [{"conditions" => [{
        "attribute" => "dd_evaluation_telemetry_opt_out", "operator" => "ONE_OF", "value" => ["true"],
      }]}]
      flag.fetch("allocations") << {
        "key" => "fallback",
        "splits" => [{"variationKey" => "off", "shards" => [], "serialId" => 101}],
        "doLog" => true,
      }
      JSON.generate(data)
    end

    [false, true].each do |activation|
      context "with activation #{activation}" do
        let(:opt_out_enabled) { activation }

        [false, true].each do |full_data|
          context "with full evaluation data #{full_data}" do
            let(:observe_full_evaluation_data) { full_data }

            [false, true, "true"].each do |value|
              it "retains #{value.inspect} for native targeting and exposure attributes" do
                trace.measure("root") do
                  2.times do
                    details = evaluate("subject", value)
                    expect(details.value).to eq((value == false) ? "disabled" : "enabled")
                    expect(details.variant).to eq((value == false) ? "off" : "on")
                    expect(details.reason).to eq((value == false) ? "STATIC" : "TARGETING_MATCH")
                    expect(details.error_code).to be_nil
                  end
                end

                expect_signals(evaluations: (activation && value == true) ? 0 : 2, exposures: 1)
                exposure = exposure_payloads.flat_map { |payload| payload[:exposures] }.first
                expect(exposure[:subject]).to eq(
                  id: "subject", attributes: {"dd_evaluation_telemetry_opt_out" => value},
                )
                evp_payloads.flat_map { |payload| payload["flagEvaluations"] }.each do |event|
                  if full_data
                    expect(event["context"]["evaluation"]).to eq("dd_evaluation_telemetry_opt_out" => value)
                    expect(event["targeting_key"]).to eq("subject")
                  else
                    expect(event).not_to have_key("context")
                    expect(event["targeting_key"]).to eq("sha256_#{Digest::SHA256.hexdigest("subject")}")
                  end
                end
              end
            end
          end
        end

        it "uses ordinary exposure deduplication when targeting changes the assignment" do
          trace.measure("root") do
            [false, true, false].each do |value|
              expect(evaluate("same-subject", value).variant).to eq(value ? "on" : "off")
            end
          end

          expect_signals(evaluations: activation ? 2 : 3, exposures: 3)
          exposures = exposure_payloads.flat_map { |payload| payload[:exposures] }
          expect(exposures.map { |exposure| exposure[:subject][:attributes] }).to eq(
            [false, true, false].map { |value| {"dd_evaluation_telemetry_opt_out" => value} },
          )
        end
      end
    end
  end

  context "with environment activation" do
    subject(:provider) { Datadog::OpenFeature::Provider.new }

    with_env "DD_FEATURE_FLAGS_EVALUATION_TELEMETRY_PER_SUBJECT_OPT_OUT_ENABLED" => "true"

    it "suppresses evaluation signals through environment activation and preserves the assignment and exposure" do
      trace.measure("root") do
        details = evaluate("subject", true)
        expect(details.value).to eq("enabled")
        expect(details.variant).to eq("on")
        expect(details.reason).to eq("STATIC")
      end

      expect_signals(evaluations: 0, exposures: 1)
    end

    it "still requires each subject to opt out with boolean true" do
      trace.measure("root") do
        evaluate("allowed", false)
        evaluate("invalid", "true")
        client.fetch_string_value(
          flag_key: "flag", default_value: "fallback",
          evaluation_context: OpenFeature::SDK::EvaluationContext.new(targeting_key: "missing"),
        )
      end

      expect_signals(evaluations: 3, exposures: 3)
    end

    it "retains its activation snapshot after environment and settings changes" do
      provider
      ClimateControl.modify("DD_FEATURE_FLAGS_EVALUATION_TELEMETRY_PER_SUBJECT_OPT_OUT_ENABLED" => "false") do
        Datadog.configuration.feature_flags.evaluation_telemetry_per_subject_opt_out_enabled = false
        trace.measure("root") { evaluate("subject", true) }
      end

      expect_signals(evaluations: 0, exposures: 1)
    end

    context "with an explicit false provider option" do
      subject(:provider) do
        Datadog::OpenFeature::Provider.new(enable_evaluation_telemetry_opt_out_parameter: false)
      end

      it "overrides the enabled environment setting" do
        trace.measure("root") { evaluate("subject", true) }

        expect_signals(evaluations: 1, exposures: 1)
      end
    end
  end

  [nil, "false", "invalid"].each do |environment_value|
    context "with environment activation set to #{environment_value.inspect}" do
      subject(:provider) { Datadog::OpenFeature::Provider.new }

      with_env "DD_FEATURE_FLAGS_EVALUATION_TELEMETRY_PER_SUBJECT_OPT_OUT_ENABLED" => environment_value

      it "retains evaluation signals" do
        trace.measure("root") { evaluate("subject", true) }

        expect_signals(evaluations: 1, exposures: 1)
      end
    end
  end

  context "with disabled environment activation and an explicit true provider option" do
    with_env "DD_FEATURE_FLAGS_EVALUATION_TELEMETRY_PER_SUBJECT_OPT_OUT_ENABLED" => "false"

    it "uses the explicit provider option" do
      trace.measure("root") { evaluate("subject", true) }

      expect_signals(evaluations: 0, exposures: 1)
    end
  end

  it "preserves queued data and exposure deduplication when the same subject changes its decision" do
    trace.measure("root") do
      [false, true, false].each { |value| expect(evaluate("same-subject", value).variant).to eq("on") }
    end

    expect_signals(evaluations: 2, exposures: 1)
    expect(span_hook).to have_received(:capture).twice
  end

  it "uses API, client, and invocation context precedence" do
    api_configuration.evaluation_context = context("api", true)
    client_with_context = OpenFeature::SDK::Client.new(provider: provider, evaluation_context: context("client", false))
    trace.measure("root") do
      client.fetch_string_value(flag_key: "flag", default_value: "fallback")
      client_with_context.fetch_string_value(flag_key: "flag", default_value: "fallback")
      client_with_context.fetch_string_value(
        flag_key: "flag", default_value: "fallback", evaluation_context: context("invocation", true),
      )
    end

    expect_signals(evaluations: 1, exposures: 3)
    expect(span_hook).to have_received(:capture).once
  end

  it "uses context returned by application before hooks and preserves all application hook stages" do
    allow(application_hook).to receive(:before).and_return(context("subject", true))
    trace.measure("root") { evaluate("subject", false, hooks: [application_hook]) }

    expect_signals(evaluations: 0, exposures: 1)
    expect(application_hook).to have_received(:before).once
    expect(application_hook).to have_received(:after).once
    expect(application_hook).to have_received(:finally).once
  end

  it "permits telemetry when an application before hook overrides opt-out with false" do
    allow(application_hook).to receive(:before).and_return(context("subject", false))
    trace.measure("root") { evaluate("subject", true, hooks: [application_hook]) }

    expect_signals(evaluations: 1, exposures: 1)
    expect(span_hook).to have_received(:capture).once
  end

  it "suppresses evaluation signals when an application before hook fails" do
    allow(application_hook).to receive(:before).and_raise("application before failure")
    details = nil
    trace.measure("root") { details = evaluate("subject", true, hooks: [application_hook]) }

    expect(details.value).to eq("fallback")
    expect(details.error_code).to eq("GENERAL")
    expect(application_hook).to have_received(:error).once
    expect(application_hook).to have_received(:finally).once
    expect_signals(evaluations: 0, exposures: 0)
  end

  it "preserves the default and error from a failed application after hook" do
    allow(application_hook).to receive(:after).and_raise("application after failure")
    details = nil
    trace.measure("root") { details = evaluate("subject", true, hooks: [application_hook]) }

    expect(details.value).to eq("fallback")
    expect(details.error_code).to eq("GENERAL")
    expect(application_hook).to have_received(:error).once
    expect_signals(evaluations: 0, exposures: 1)
  end

  it "preserves native error defaults" do
    details = nil
    trace.measure("root") do
      details = client.fetch_string_details(
        flag_key: "missing", default_value: "fallback", evaluation_context: context("subject", true),
      )
    end

    expect(details.value).to eq("fallback")
    expect(details.error_code).to eq("FLAG_NOT_FOUND")
    expect(details.reason).to eq("ERROR")
    expect_signals(evaluations: 0, exposures: 0)
  end

  it "preserves native type mismatch defaults" do
    details = nil
    trace.measure("root") do
      details = client.fetch_boolean_details(
        flag_key: "flag", default_value: false, evaluation_context: context("subject", true),
      )
    end

    expect(details.value).to be(false)
    expect(details.error_code).to eq("TYPE_MISMATCH")
    expect_signals(evaluations: 0, exposures: 0)
  end

  it "gates direct provider span enrichment" do
    trace.measure("root") do
      details = provider.fetch_string_value(
        flag_key: "flag", default_value: "fallback", evaluation_context: context("subject", true),
      )
      expect(details.value).to eq("enabled")
    end

    expect_signals(evaluations: 0, exposures: 1)
  end

  if OpenFeature::SDK::Configuration.method_defined?(:provider_tracked?)
    it "suppresses SDK short-circuit error signals when the provider becomes fatal" do
      api_configuration.set_provider_and_wait(provider)
      provider.emit_event(OpenFeature::SDK::ProviderEvent::PROVIDER_ERROR, error_code: "PROVIDER_FATAL")
      details = nil
      trace.measure("root") { details = evaluate("subject", true) }

      expect(details.value).to eq("fallback")
      expect(details.error_code).to eq("PROVIDER_FATAL")
      expect_signals(evaluations: 0, exposures: 0)
    end

    it "cannot use opt-out from a before hook when the provider becomes fatal" do
      api_configuration.set_provider_and_wait(provider)
      provider.emit_event(OpenFeature::SDK::ProviderEvent::PROVIDER_ERROR, error_code: "PROVIDER_FATAL")
      allow(application_hook).to receive(:before).and_return(context("subject", true))
      details = nil
      trace.measure("root") { details = evaluate("subject", false, hooks: [application_hook]) }

      expect(details.value).to eq("fallback")
      expect(details.error_code).to eq("PROVIDER_FATAL")
      expect(application_hook).not_to have_received(:before)
      expect_signals(evaluations: 1, exposures: 0, annotations: 0)
    end

    [false, true].each do |invocation_opt_out|
      it "uses invocation opt-out #{invocation_opt_out} without before hooks during initialization" do
        entered = Queue.new
        resume = Queue.new
        allow(Datadog.send(:components).open_feature).to receive(:wait_for_configuration) do
          entered << true
          resume.pop
          Datadog::OpenFeature::Component::CONFIGURATION_READY
        end
        allow(application_hook).to receive(:before).and_return(context("subject", true))
        thread = Thread.new { api_configuration.set_provider_and_wait(provider) }
        Timeout.timeout(5) { entered.pop }
        details = nil
        trace.measure("root") { details = evaluate("subject", invocation_opt_out, hooks: [application_hook]) }

        expect(details.value).to eq("fallback")
        expect(details.error_code).to eq("PROVIDER_NOT_READY")
        expect(application_hook).not_to have_received(:before)
        expect_signals(evaluations: invocation_opt_out ? 0 : 1, exposures: 0, annotations: 0)
      ensure
        resume << true
        thread&.join(5)
        thread&.kill if thread&.alive?
      end
    end
  end

  it "isolates nested evaluations" do
    allow(application_hook).to receive(:after) { evaluate("inner", false) }
    trace.measure("root") { evaluate("outer", true, hooks: [application_hook]) }

    expect_signals(evaluations: 1, exposures: 2)
    expect(span_hook).to have_received(:capture).once
  end

  it "isolates concurrent subjects" do
    entered = Queue.new
    resume = Queue.new
    allow(application_hook).to receive(:after) do
      entered << true
      resume.pop
    end
    thread = nil
    trace.measure("root") do
      thread = Thread.new { evaluate("opted-out", true, hooks: [application_hook]) }
      Timeout.timeout(5) { entered.pop }
      expect(evaluate("allowed", false).value).to eq("enabled")
      resume << true
      expect(thread.join(5)).not_to be_nil
      expect(thread.value.value).to eq("enabled")
    end

    expect_signals(evaluations: 1, exposures: 2)
    expect(span_hook).to have_received(:capture).once
  ensure
    resume << true
    thread&.join(5)
    thread&.kill if thread&.alive?
  end

  it "keeps provider activation isolated when providers share the component" do
    unrestricted = OpenFeature::SDK::Client.new(provider: Datadog::OpenFeature::Provider.new)
    trace.measure("root") do
      evaluate("opted-out", true)
      unrestricted.fetch_string_value(
        flag_key: "flag", default_value: "fallback", evaluation_context: context("allowed", true),
      )
    end

    expect_signals(evaluations: 1, exposures: 2)
    expect(span_hook).to have_received(:capture).once
  end

  context "with full evaluation data enabled" do
    let(:observe_full_evaluation_data) { true }

    it "keeps allowed event context and suppresses opted-out events" do
      trace.measure("root") do
        evaluate("opted-out", true)
        evaluate("allowed", false)
      end

      expect_signals(evaluations: 1, exposures: 2)
      expect(span_hook).to have_received(:capture).once
      event = evp_payloads.first["flagEvaluations"].first
      expect(event["targeting_key"]).to eq("allowed")
      expect(event["context"]["evaluation"]).to include("dd_evaluation_telemetry_opt_out" => false)
    end
  end

  it "preserves unrelated metrics and manual span tags" do
    meter_provider.meter("application").create_counter("application.requests").add(1)
    trace.measure("root") do |span|
      span.set_tag("application.tag", "retained")
      evaluate("subject", true)
    end

    expect_signals(evaluations: 0, exposures: 1)
    expect(trace.get_tag("application.tag")).to eq("retained")
    metric = metric_reader.metric_snapshots.find { |entry| entry.name == "application.requests" }
    expect(metric.data_points.sum(&:value)).to eq(1)
  end
end
