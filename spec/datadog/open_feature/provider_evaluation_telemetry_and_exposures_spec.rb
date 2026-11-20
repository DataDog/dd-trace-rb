# frozen_string_literal: true

require "spec_helper"
require "open_feature/sdk"
require "opentelemetry-metrics-sdk"
require "datadog/open_feature/provider"
require "datadog/open_feature/component"

RSpec.describe "OpenFeature evaluation telemetry and exposures switches" do
  with_env "DD_FEATURE_FLAGS_EVALUATION_TELEMETRY_ENABLED" => nil,
    "DD_FEATURE_FLAGS_EXPOSURES_ENABLED" => nil

  let(:logger) { logger_allowing_debug }
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component, report: nil, inc: nil) }
  let(:evp_payloads) { [] }
  let(:exposure_payloads) { [] }
  let(:customer_evaluations) { [] }
  let(:transport) { instance_double(Datadog::OpenFeature::Transport::HTTP) }
  let(:writer) { Datadog::OpenFeature::FlagEvaluation::Writer.new(transport: transport, logger: logger) }
  let(:worker) do
    Datadog::OpenFeature::Exposures::Worker.new(
      settings: Datadog.configuration, transport: transport, telemetry: telemetry, logger: logger,
    )
  end
  let(:reporter) { Datadog::OpenFeature::Exposures::Reporter.new(worker, logger: logger) }
  let(:engine) { Datadog::OpenFeature::EvaluationEngine.new(telemetry: telemetry, logger: logger) }
  let(:metrics) { Datadog::OpenFeature::Metrics::FlagEvalMetrics.new(telemetry: telemetry, logger: logger) }
  let(:meter_provider) { OpenTelemetry::SDK::Metrics::MeterProvider.new }
  let(:metric_reader) { OpenTelemetry::SDK::Metrics::Export::InMemoryMetricPullExporter.new }
  let(:span_hook) do
    Datadog::OpenFeature::Hooks::SpanEnrichmentHook.new(
      Datadog::OpenFeature::Hooks::SpanEnrichmentHook::SpanEnrichmentStateStore.new, logger: logger,
    )
  end
  let(:trace) { Datadog::Tracing::TraceOperation.new }
  let(:api_configuration) { OpenFeature::SDK::Configuration.new }
  let(:customer_hook) do
    Datadog::OpenFeature::ExposureHook.new { |evaluation| customer_evaluations << evaluation }
  end
  # One component, and so one exposure cache, serves every provider in the process.
  let(:component) do
    instance_double(
      Datadog::OpenFeature::Component,
      engine: engine,
      flag_eval_evp_hook: Datadog::OpenFeature::Hooks::FlagEvalEVPHook.new(writer),
      flag_eval_metrics_hook: Datadog::OpenFeature::Hooks::FlagEvalMetricsHook.new(metrics),
      debug_logging_hook: nil,
      exposure_logging_hook: Datadog::OpenFeature::Hooks::ExposureLoggingHook.new(
        reporter, telemetry: telemetry, logger: logger,
      ),
      span_enrichment_hook: span_hook,
      wait_for_configuration: Datadog::OpenFeature::Component::CONFIGURATION_READY,
    )
  end
  let(:configuration) do
    JSON.generate(
      "createdAt" => "2024-04-17T19:40:53.716Z",
      "environment" => {"name" => "test"},
      "flags" => {
        "flag" => {
          "key" => "flag", "enabled" => true, "variationType" => "STRING",
          "variations" => {
            "on" => {"key" => "on", "value" => "enabled"},
            "off" => {"key" => "off", "value" => "disabled"},
          },
          "allocations" => [
            {
              "key" => "experiment",
              "splits" => [{"variationKey" => "on", "shards" => [], "serialId" => 100}],
              "doLog" => true,
            },
            {
              "key" => "fallback",
              "splits" => [{"variationKey" => "off", "shards" => []}],
              "doLog" => false,
            },
          ],
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
    api_configuration.send(:reset)
  end

  def client_for(provider)
    OpenFeature::SDK::Client.new(provider: provider).tap { |client| client.hooks << customer_hook }
  end

  def evaluate(client, subject = "user-1", **attributes)
    details = nil
    trace.measure("root") do
      details = client.fetch_string_details(
        flag_key: "flag", default_value: "fallback",
        evaluation_context: OpenFeature::SDK::EvaluationContext.new(targeting_key: subject, **attributes),
      )
    end
    details
  end

  def telemetry_counts
    writer.send(:drain_and_flush)
    metric_reader.pull
    {
      evp: evp_payloads.sum { |payload| payload["flagEvaluations"].sum { |event| event["evaluation_count"] } },
      metrics: metric_reader.metric_snapshots.select { |metric| metric.name == "feature_flag.evaluations" }
        .sum { |metric| metric.data_points.sum(&:value) },
      span_annotations: ["ffe_flags_enc", "ffe_subjects_enc", "ffe_runtime_defaults"]
        .count { |tag| trace.get_tag(tag) },
    }
  end

  def sent_exposures
    events = worker.dequeue
    worker.send(:send_events, *events) unless events.empty?
    exposure_payloads.flat_map { |payload| payload[:exposures] }
  end

  def no_telemetry
    {evp: 0, metrics: 0, span_annotations: 0}
  end

  it "produces evaluation telemetry and exposures by default" do
    details = evaluate(client_for(Datadog::OpenFeature::Provider.new))

    expect(details.variant).to eq("on")
    expect(telemetry_counts).to eq(evp: 1, metrics: 1, span_annotations: 2)
    expect(sent_exposures.size).to eq(1)
    expect(customer_evaluations.map(&:should_send?)).to eq([true])
  end

  it "keeps exposures when evaluation telemetry is disabled" do
    details = evaluate(client_for(Datadog::OpenFeature::Provider.new(evaluation_telemetry_enabled: false)))

    expect(details.variant).to eq("on")
    expect(telemetry_counts).to eq(no_telemetry)
    expect(sent_exposures.size).to eq(1)
    expect(customer_evaluations.map(&:should_send?)).to eq([true])
  end

  it "keeps evaluation telemetry when exposures are disabled" do
    details = evaluate(client_for(Datadog::OpenFeature::Provider.new(exposures_enabled: false)))

    expect(details.value).to eq("enabled")
    expect(details.variant).to eq("on")
    expect(details.flag_metadata).to include(Datadog::OpenFeature::Ext::METADATA_ALLOCATION_KEY => "experiment")
    expect(details.flag_metadata).not_to include(Datadog::OpenFeature::Ext::METADATA_DO_LOG)
    # Without an exposure, the span records the flag but not the subject.
    expect(telemetry_counts).to eq(evp: 1, metrics: 1, span_annotations: 1)
    expect(trace.get_tag("ffe_subjects_enc")).to be_nil
    expect(sent_exposures).to be_empty
    expect(customer_evaluations.map(&:exposure?)).to eq([false])
    expect(customer_evaluations.map(&:should_send?)).to eq([false])
    expect(customer_evaluations.map(&:cache_hit?)).to eq([false])
  end

  it "does not let an inspection suppress the later exposure of the same subject" do
    peek = client_for(Datadog::OpenFeature::Provider.new(evaluation_telemetry_enabled: false, exposures_enabled: false))
    live = client_for(Datadog::OpenFeature::Provider.new)

    inspected = evaluate(peek)
    evaluate(peek)
    expect(telemetry_counts).to eq(no_telemetry)
    expect(sent_exposures).to be_empty

    exposed = evaluate(live)

    expect(exposed.variant).to eq(inspected.variant)
    expect(exposed.value).to eq(inspected.value)
    exposures = sent_exposures
    expect(exposures.size).to eq(1)
    expect(exposures.first[:subject][:id]).to eq("user-1")
    expect(exposures.first[:variant][:key]).to eq(inspected.variant)
    expect(customer_evaluations.map(&:exposure?)).to eq([false, false, true])
    expect(customer_evaluations.last.should_send?).to be(true)
  end

  context "when the environment disables both" do
    with_env "DD_FEATURE_FLAGS_EVALUATION_TELEMETRY_ENABLED" => "false",
      "DD_FEATURE_FLAGS_EXPOSURES_ENABLED" => "false"

    it "applies to a provider without options" do
      provider = Datadog::OpenFeature::Provider.new

      expect(provider.hooks).to be_empty
      details = evaluate(client_for(provider))
      expect(details.variant).to eq("on")
      expect(telemetry_counts).to eq(no_telemetry)
      expect(sent_exposures).to be_empty
    end
  end

  [true, false].each do |enabled|
    context "when the options are #{enabled} and the environment is #{!enabled}" do
      with_env "DD_FEATURE_FLAGS_EVALUATION_TELEMETRY_ENABLED" => (!enabled).to_s,
        "DD_FEATURE_FLAGS_EXPOSURES_ENABLED" => (!enabled).to_s

      it "uses the options" do
        provider = Datadog::OpenFeature::Provider.new(
          evaluation_telemetry_enabled: enabled, exposures_enabled: enabled,
        )

        evaluate(client_for(provider))

        expect(telemetry_counts).to eq(enabled ? {evp: 1, metrics: 1, span_annotations: 2} : no_telemetry)
        expect(sent_exposures.size).to eq(enabled ? 1 : 0)
      end
    end
  end

  it "reads the configuration once, at construction" do
    Datadog.configuration.feature_flags.exposures_enabled = false
    provider = Datadog::OpenFeature::Provider.new
    Datadog.configuration.feature_flags.exposures_enabled = true
    Datadog.configuration.feature_flags.evaluation_telemetry_enabled = false

    evaluate(client_for(provider))

    expect(telemetry_counts).to eq(evp: 1, metrics: 1, span_annotations: 1)
    expect(sent_exposures).to be_empty
  end

  [:evaluation_telemetry_enabled, :exposures_enabled].each do |option|
    ["false", 0, :off].each do |value|
      it "rejects #{option}: #{value.inspect}" do
        expect { Datadog::OpenFeature::Provider.new(option => value) }
          .to raise_error(ArgumentError, /#{option}/)
      end
    end
  end

  context "with immediate experimentation opt-out" do
    before do
      unless Datadog::Core::FeatureFlags::Configuration.method_defined?(:get_assignment_with_options)
        skip "requires a libdatadog build with evaluation options"
      end
    end

    it "assigns an opted-out subject the same way with exposures disabled" do
      peek = client_for(
        Datadog::OpenFeature::Provider.new(experimentation_opt_out_mode: :immediate, exposures_enabled: false),
      )
      live = client_for(Datadog::OpenFeature::Provider.new(experimentation_opt_out_mode: :immediate))

      inspected = evaluate(peek, dd_experimentation_opt_out_at: "2026-10-19T12:00:00Z")
      exposed = evaluate(live, dd_experimentation_opt_out_at: "2026-10-19T12:00:00Z")

      expect(inspected.variant).to eq("off")
      expect(exposed.variant).to eq(inspected.variant)
      expect(sent_exposures).to be_empty
    end
  end
end
