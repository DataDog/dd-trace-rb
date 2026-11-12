# frozen_string_literal: true

require "spec_helper"
require "open_feature/sdk"
require "datadog/open_feature/provider"
require "datadog/open_feature/evaluation_engine"
require "datadog/open_feature/exposures/reporter"
require "datadog/open_feature/hooks/flag_eval_evp_hook"
require "datadog/open_feature/hooks/flag_eval_metrics_hook"

RSpec.describe Datadog::OpenFeature::Hooks::ExposureLoggingHook do
  let(:provider) { Datadog::OpenFeature::Provider.new(enable_evaluation_telemetry_opt_out_parameter: false) }
  let(:client) { OpenFeature::SDK::Client.new(provider: provider) }
  let(:context) { OpenFeature::SDK::EvaluationContext.new(targeting_key: +"subject", marker: +"original") }
  let(:worker) { instance_double(Datadog::OpenFeature::Exposures::Worker) }
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component, report: nil) }
  let(:logger) { instance_double(Datadog::Core::Logger, debug: nil, debug?: false) }
  let(:reporter) { Datadog::OpenFeature::Exposures::Reporter.new(worker, telemetry: telemetry, logger: logger) }
  let(:engine) { Datadog::OpenFeature::EvaluationEngine.new(reporter, telemetry: telemetry, logger: logger) }
  let(:writer) { instance_double(Datadog::OpenFeature::FlagEvaluation::Writer) }
  let(:evp_hook) { Datadog::OpenFeature::Hooks::FlagEvalEVPHook.new(writer) }
  let(:component) do
    instance_double(Datadog::OpenFeature::Component,
      flag_eval_evp_hook: evp_hook, flag_eval_metrics_hook: nil, debug_logging_hook: nil, span_enrichment_hook: nil)
  end
  let(:components) { instance_double(Datadog::Core::Configuration::Components, open_feature: component) }
  let(:exposures) { [] }
  let(:observations) { [] }
  let(:hook) { instance_double(OpenFeature::SDK::Hooks::Hook) }

  before do
    skip "requires the prerequisite-aware native library" unless Datadog::Core::FeatureFlags.evaluator_capabilities.include?("dependent-flag-variant-key-v1")
    allow(Datadog).to receive(:send).and_call_original
    allow(Datadog).to receive(:send).with(:components).and_return(components)
    allow(Datadog::OpenFeature).to receive(:engine).and_return(engine)
    allow(Datadog).to receive(:logger).and_return(logger)
    allow(worker).to receive(:enqueue) do |event|
      exposures << event
      true
    end
    allow(writer).to receive(:enqueue) { |**event| observations << event }
    engine.reconfigure!(File.read(File.expand_path("../../../fixtures/ffe/dependent_flags.json", __dir__)))
  end

  def evaluate(hooks: [], flag_key: "root")
    client.fetch_boolean_details(flag_key: flag_key, default_value: false, evaluation_context: context, hooks: hooks)
  end

  it "discards exposures on an after hook failure and leaves a same-subject retry unexposed" do
    allow(hook).to receive(:after).and_raise("application hook failed")

    failed = evaluate(hooks: [hook])

    expect(failed.value).to be(false)
    expect(failed.error_code).to eq("GENERAL")
    expect(exposures).to eq([])
    expect(observations.map { |event| [event[:flag_key], event[:error_message]] }).to eq([["parent", nil], ["root", "GENERAL"]])

    expect(evaluate.value).to be(true)
    expect(exposures.map { |event| event[:flag][:key] }).to eq(["parent", "root"])
  end

  it "does not publish or retain another evaluation when a before hook fails" do
    allow(hook).to receive(:before).and_raise("before hook failed")

    expect(evaluate(hooks: [hook]).error_code).to eq("GENERAL")
    expect(exposures).to eq([])
    expect(evaluate.value).to be(true)
    expect(exposures.map { |event| event[:flag][:key] }).to eq(["parent", "root"])
  end

  it "keeps a successful nested evaluation independent of its failed caller" do
    allow(hook).to receive(:after) do
      expect(evaluate(flag_key: "parent").value).to be(true)
      raise "outer after hook failed"
    end

    expect(evaluate(hooks: [hook]).error_code).to eq("GENERAL")
    expect(exposures.map { |event| event[:flag][:key] }).to eq(["parent"])
    expect(evaluate.value).to be(true)
    expect(exposures.map { |event| event[:flag][:key] }).to eq(["parent", "root"])
  end

  it "keeps overlapping evaluations independent when one after hook fails" do
    entered = Queue.new
    release = Queue.new
    allow(hook).to receive(:after) do
      entered << true
      release.pop
      raise "concurrent after hook failed"
    end
    failed = Thread.new { evaluate(hooks: [hook]) }
    entered.pop

    expect(exposures).to eq([])
    expect(evaluate.value).to be(true)
    release << true
    expect(failed.value.error_code).to eq("GENERAL")
    expect(exposures.map { |event| event[:flag][:key] }).to eq(["parent", "root"])
  ensure
    release << true if release
    failed&.join
  end

  it "preserves exposure decisions and subjects when an after hook mutates SDK details" do
    allow(hook).to receive(:after) do |hook_context:, evaluation_details:, **|
      hook_context.evaluation_context.fields.fetch("targeting_key").replace("changed-subject")
      hook_context.evaluation_context.fields.fetch("marker").replace("changed-marker")
      evaluation_details.variant.replace("changed-variant")
    end

    expect(evaluate(hooks: [hook]).value).to be(true)
    expect(exposures.map { |event| event[:subject][:id] }).to eq(["subject", "subject"])
    expect(exposures.map { |event| event[:subject][:attributes]["marker"] }).to eq(["original", "original"])
    expect(exposures.map { |event| event[:variant][:key] }).to eq(["on", "on"])
  end

  it "leaves direct provider results pending until a client finalizes them" do
    result = provider.fetch_boolean_value(flag_key: "root", default_value: false, evaluation_context: context)

    expect(result.value).to be(true)
    expect(exposures).to eq([])
    expect(evaluate.value).to be(true)
    expect(exposures.map { |event| event[:flag][:key] }).to eq(["parent", "root"])
  end
end
