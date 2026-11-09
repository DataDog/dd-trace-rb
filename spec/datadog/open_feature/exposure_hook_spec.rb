# frozen_string_literal: true

require "spec_helper"
require "open_feature/sdk"
require "datadog/open_feature/provider"
require "datadog/open_feature/component"

RSpec.describe Datadog::OpenFeature::ExposureHook do
  subject(:hook) { described_class.new { |evaluation| evaluations << evaluation } }

  let(:evaluations) { [] }
  let(:sent_events) { [] }
  let(:logger) { instance_double(Datadog::Core::Logger, debug: nil, debug?: false, warn: nil, error: nil) }
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component, report: nil) }
  let(:worker) { instance_double(Datadog::OpenFeature::Exposures::Worker) }
  let(:datadog_logging_enabled) { true }
  let(:reporter) do
    Datadog::OpenFeature::Exposures::Reporter.new(
      worker, logger: logger, datadog_logging_enabled: datadog_logging_enabled,
    )
  end
  let(:engine) { Datadog::OpenFeature::EvaluationEngine.new(telemetry: telemetry, logger: logger) }
  let(:provider) { Datadog::OpenFeature::Provider.new }
  let(:api_configuration) { OpenFeature::SDK::Configuration.new }
  let(:client) { OpenFeature::SDK::Client.new(provider: provider).tap { |c| c.hooks << hook } }
  let(:features) do
    [
      {"key" => "holdout.key", "value" => "h-1", "destinations" => ["HOOK"]},
      {"key" => "holdout.assignment_group", "value" => "status_quo", "destinations" => ["HOOK"]},
      {"key" => "holdout.should_include_in_holdout_analysis", "value" => false, "destinations" => ["HOOK"]},
      {"key" => "exposure.only", "value" => 1.5, "destinations" => ["EXPOSURE"]},
      {"key" => "evaluation.only", "value" => true, "destinations" => ["EVALUATION"]},
    ]
  end

  def configuration(variant: "on", serial_id: 100, do_log: true, split_features: features)
    split = {"variationKey" => variant, "shards" => [], "serialId" => serial_id}
    split["features"] = split_features if split_features
    JSON.generate(
      "createdAt" => "2024-04-17T19:40:53.716Z",
      "environment" => {"name" => "test"},
      "flags" => {
        "flag" => {
          "key" => "flag", "enabled" => true, "variationType" => "STRING",
          "variations" => {"on" => {"key" => "on", "value" => "enabled"}, "off" => {"key" => "off", "value" => "disabled"}},
          "allocations" => [{"key" => "experiment", "splits" => [split], "doLog" => do_log}],
        },
      },
    )
  end

  def evaluate(subject = "subject-1", **options)
    client.fetch_string_details(
      flag_key: "flag", default_value: "fallback",
      evaluation_context: OpenFeature::SDK::EvaluationContext.new(targeting_key: subject), **options,
    )
  end

  before do
    allow(Datadog).to receive(:logger).and_return(logger)
    allow(OpenFeature::SDK::API.instance).to receive(:configuration).and_return(api_configuration)
    allow(worker).to receive(:enqueue) { |event| sent_events << event }
    component = instance_double(
      Datadog::OpenFeature::Component,
      engine: engine,
      exposure_logging_hook: Datadog::OpenFeature::Hooks::ExposureLoggingHook.new(
        reporter, telemetry: telemetry, logger: logger,
      ),
      flag_eval_metrics_hook: nil,
      flag_eval_evp_hook: nil,
      debug_logging_hook: nil,
      span_enrichment_hook: nil,
    )
    components = instance_double(Datadog::Core::Configuration::Components, open_feature: component)
    allow(Datadog).to receive(:send).and_call_original
    allow(Datadog).to receive(:send).with(:components).and_return(components)
    allow(Datadog::OpenFeature).to receive(:engine).and_return(engine)
    engine.reconfigure!(configuration)
  end

  after { api_configuration.send(:reset) }

  describe "the first evaluation of a subject" do
    it "is a new exposure that Datadog receives" do
      evaluate

      evaluation = evaluations.last
      expect(evaluation.exposure?).to be(true)
      expect(evaluation.cache_hit?).to be(false)
      expect(evaluation.should_send?).to be(true)
      expect(sent_events.size).to eq(1)
    end

    it "exposes the evaluation fields" do
      evaluate

      evaluation = evaluations.last
      expect(evaluation.flag_key).to eq("flag")
      expect(evaluation.variant).to eq("on")
      expect(evaluation.allocation_key).to eq("experiment")
      expect(evaluation.split_serial_id).to eq(100)
      expect(evaluation.targeting_key).to eq("subject-1")
      expect(evaluation.evaluation_details.value).to eq("enabled")
    end

    it "exposes only the HOOK features" do
      evaluate

      expect(evaluations.last.features).to eq(
        "holdout.key" => "h-1",
        "holdout.assignment_group" => "status_quo",
        "holdout.should_include_in_holdout_analysis" => false,
      )
      expect(evaluations.last.features).to be_frozen
    end

    it "puts the EXPOSURE features, and no others, on the exposure event" do
      evaluate

      expect(sent_events.last[:features]).to eq("exposure.only" => 1.5)
    end

    it "stamps the verdict and the exposure fields into the returned flag metadata" do
      details = evaluate

      expect(details.flag_metadata).to include(
        "__dd_exposure_cache_hit" => false,
        "__dd_do_log" => true,
        "__dd_split_serial_id" => 100,
        "__dd_feature.holdout.key" => "h-1",
        "__dd_exposure_feature.exposure.only" => 1.5,
        "__dd_evaluation_feature.evaluation.only" => true,
      )
    end
  end

  describe "a repeated evaluation" do
    it "is a cache hit that Datadog does not receive again" do
      evaluate
      evaluate

      evaluation = evaluations.last
      expect(evaluation.exposure?).to be(true)
      expect(evaluation.cache_hit?).to be(true)
      expect(evaluation.should_send?).to be(false)
      expect(sent_events.size).to eq(1)
    end

    it "is a new exposure for another subject" do
      evaluate("subject-1")
      evaluate("subject-2")

      expect(evaluations.map(&:should_send?)).to eq([true, true])
    end
  end

  describe "a change of assignment for the same subject" do
    it "is a new exposure when the variant changes" do
      evaluate
      engine.reconfigure!(configuration(variant: "off"))
      evaluate

      expect(evaluations.map(&:should_send?)).to eq([true, true])
      expect(sent_events.map { |event| event[:variant][:key] }).to eq(["on", "off"])
    end

    it "is a new exposure when the serial id changes" do
      evaluate
      engine.reconfigure!(configuration(serial_id: 101))
      evaluate

      expect(evaluations.map(&:should_send?)).to eq([true, true])
      expect(sent_events.map { |event| event[:serial_id] }).to eq([100, 101])
    end
  end

  describe "a failed evaluation" do
    let(:failing_after_hook) do
      Class.new do
        include OpenFeature::SDK::Hooks::Hook

        def after(**_options)
          raise "rejected by the application"
        end
      end.new
    end

    it "sends and records nothing" do
      evaluate(hooks: [failing_after_hook])

      expect(evaluations.last.exposure?).to be(false)
      expect(evaluations.last.should_send?).to be(false)
      expect(sent_events).to be_empty

      evaluate

      expect(evaluations.last.should_send?).to be(true)
      expect(sent_events.size).to eq(1)
    end

    it "sends nothing for a missing flag" do
      client.fetch_string_details(
        flag_key: "missing", default_value: "fallback",
        evaluation_context: OpenFeature::SDK::EvaluationContext.new(targeting_key: "subject-1"),
      )

      expect(evaluations.last.exposure?).to be(false)
      expect(sent_events).to be_empty
    end
  end

  context "without an evaluation context" do
    it "is an exposure that is neither sent nor recorded" do
      client.fetch_string_details(flag_key: "flag", default_value: "fallback")

      expect(evaluations.last.exposure?).to be(true)
      expect(evaluations.last.should_send?).to be(false)
      expect(evaluations.last.cache_hit?).to be(false)
      expect(sent_events).to be_empty
    end
  end

  context "when the allocation does not log exposures" do
    before { engine.reconfigure!(configuration(do_log: false)) }

    it "is not an exposure and nothing is sent" do
      details = evaluate

      expect(evaluations.last.exposure?).to be(false)
      expect(evaluations.last.should_send?).to be(false)
      expect(details.flag_metadata.keys).not_to include("__dd_do_log", "__dd_split_serial_id", "__dd_exposure_cache_hit")
      expect(sent_events).to be_empty
    end
  end

  context "when the split has no features" do
    before { engine.reconfigure!(configuration(split_features: nil)) }

    it "adds no feature metadata" do
      details = evaluate

      expect(details.flag_metadata.keys.grep(/feature\./)).to be_empty
      expect(evaluations.last.features).to eq({})
      expect(sent_events.last).not_to have_key(:features)
    end
  end

  context "when Datadog exposure logging is disabled" do
    let(:datadog_logging_enabled) { false }

    it "sends nothing to Datadog while the hook still gets the same decisions" do
      evaluate
      evaluate

      expect(sent_events).to be_empty
      expect(evaluations.map(&:should_send?)).to eq([true, false])
      expect(evaluations.map(&:cache_hit?)).to eq([false, true])
    end
  end

  context "when the callback raises" do
    subject(:hook) { described_class.new { raise ArgumentError, "callback failure" } }

    it "does not affect the evaluation or the Datadog exposure" do
      details = evaluate

      expect(details.value).to eq("enabled")
      expect(details.error_code).to be_nil
      expect(sent_events.size).to eq(1)
    end

    it "warns on the first failure and logs later ones at debug level" do
      debug_messages = []
      allow(logger).to receive(:debug) { |&block| debug_messages << block.call }

      evaluate
      evaluate

      expect(logger).to have_received(:warn)
        .with(/ExposureHook callback failed for "flag": ArgumentError; later failures are logged at debug level/).once
      expect(debug_messages).to include('Feature Flags: ExposureHook callback failed for "flag": ArgumentError: callback failure')
    end

    it "contains a failure raised while logging the failure" do
      allow(logger).to receive(:warn).and_raise("logger failure")

      expect(evaluate.value).to eq("enabled")
    end
  end

  context "when the callback raises a ScriptError" do
    subject(:hook) { described_class.new { raise NotImplementedError, "not yet" } }

    it "does not affect the evaluation" do
      expect(evaluate.value).to eq("enabled")
    end
  end

  context "with a provider other than the Datadog provider" do
    let(:other_provider) { OpenFeature::SDK::Provider::InMemoryProvider.new("flag" => "other") }
    let(:client) { OpenFeature::SDK::Client.new(provider: other_provider).tap { |c| c.hooks << hook } }

    it "skips the callback and warns once" do
      2.times { evaluate }

      expect(evaluations).to be_empty
      expect(logger).to have_received(:warn).with(/requires a directly registered Datadog provider/).once
    end
  end

  describe "direct calls" do
    let(:hook_context) do
      OpenFeature::SDK::Hooks::HookContext.new(
        flag_key: "flag", flag_value_type: :string, default_value: "fallback", evaluation_context: nil,
        provider_metadata: provider.metadata,
      )
    end

    def details(error_code:, reason:)
      OpenFeature::SDK::EvaluationDetails.new(
        flag_key: "flag",
        resolution_details: OpenFeature::SDK::Provider::ResolutionDetails.new(
          value: "enabled", variant: "on", reason: reason, error_code: error_code,
          flag_metadata: {"__dd_allocation_key" => "experiment", "__dd_do_log" => true, "__dd_exposure_cache_hit" => false},
        ),
      )
    end

    it "is not an exposure when only the error code reports the failure" do
      evaluation = described_class::Evaluation.new(hook_context, details(error_code: "GENERAL", reason: "DEFAULT"))

      expect(evaluation.exposure?).to be(false)
      expect(evaluation.should_send?).to be(false)
    end

    context "when the callback and the logger both raise" do
      subject(:hook) { described_class.new { raise "callback failure" } }

      before { allow(logger).to receive(:warn).and_raise("logger failure") }

      it "does not raise from the hook" do
        expect do
          hook.finally(hook_context: hook_context, evaluation_details: details(error_code: nil, reason: "STATIC"))
        end.not_to raise_error
      end
    end
  end

  describe ".new" do
    it "accepts a callable" do
      callable = ->(evaluation) { evaluations << evaluation }
      client.hooks.replace([described_class.new(callable)])

      evaluate

      expect(evaluations.size).to eq(1)
    end

    it "rejects a callback and a block together" do
      expect { described_class.new(->(_) {}) {} }.to raise_error(ArgumentError, /not both/)
    end

    it "rejects a missing callback" do
      expect { described_class.new }.to raise_error(ArgumentError, /must respond to #call/)
    end
  end
end
