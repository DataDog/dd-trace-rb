# frozen_string_literal: true

require "libddwaf"
require "datadog/appsec/spec_helper"

RSpec.shared_context "native AppSec output" do
  let(:trace) { Datadog::Tracing::TraceOperation.new }
  let(:span) { Datadog::Tracing::SpanOperation.new("native.output") }
  let(:telemetry) { spy(Datadog::Core::Telemetry::Component) }
  let(:native_builders) { [] }
  let(:native_handles) { [] }
  let(:native_engine) do
    allow(Datadog::AppSec::WAF::HandleBuilder).to receive(:new).and_wrap_original do |original, **options|
      builder = original.call(**options)
      native_builders << builder
      allow(builder).to receive(:build_handle).and_wrap_original do |build|
        handle = build.call
        native_handles << handle
        handle
      end
      builder
    end
    settings = Datadog::Core::Configuration::Settings.new
    settings.appsec.ruleset = native_rules
    Datadog::AppSec::SecurityEngine::Engine.new(appsec_settings: settings.appsec, telemetry: telemetry)
  end
  let(:context) { Datadog::AppSec::Context.new(trace, span, native_engine.new_runner) }
  let(:output_keep) { false }
  let(:output_attributes) { {"test.trace.attribute" => {"value" => "captured"}} }
  let(:output_conditions) do
    [{
      "operator" => "match_regex",
      "parameters" => {"inputs" => [{"address" => output_address}], "regex" => ".+"},
    }]
  end
  let(:native_rules) do
    {
      "version" => "2.2",
      "rules_compat" => [{
        "id" => "trace-output", "name" => "Trace output", "tags" => {"type" => "test"},
        "conditions" => output_conditions,
        "output" => {"event" => false, "keep" => output_keep, "attributes" => output_attributes},
      }],
    }
  end

  before do
    allow(Datadog::AppSec).to receive(:telemetry).and_return(telemetry)
    allow(Datadog.configuration.appsec).to receive(:waf_timeout).and_return(1_000_000)
    context.attach
    trace.sampling_priority = 0
  end

  after { context.detach }

  around do |example|
    example.run
  ensure
    native_handles.each(&:finalize!)
    native_builders.each(&:finalize!)
  end
end

RSpec.shared_examples "a native AppSec output consumer" do |retention = :immediate|
  include_context "native AppSec output"

  it "records arbitrary attributes without a detection or retention" do
    consume

    expect(context.events.size).to eq(1)
    result = context.events.first.waf_result
    expect(result.events).to be_empty
    expect(result.actions).to be_empty
    expect(result).not_to be_match
    expect(result).not_to be_keep
    expect(context.metrics.waf.matches).to eq(0)
    expect(context.metrics.rasp.matches).to eq(0)
    expect(context.metrics.waf.errors).to eq(0)
    context.export_request_telemetry
    expect(telemetry).to have_received(:inc).with(
      "appsec", "waf.requests", 1, tags: hash_including(rule_triggered: "false"),
    )
    Datadog::AppSec::Event.record(context)
    expect(span.get_tag("test.trace.attribute")).to eq("captured")
    expect(span.tags).not_to include("appsec.event", "appsec.blocked", "_dd.appsec.json")
    expect(trace.sampling_priority).to eq(0)
  end

  context "when native OK requests retention without materialized attributes" do
    let(:output_keep) { true }
    let(:output_attributes) { {"test.trace.attribute" => {"address" => "missing.source"}} }

    it "preserves keep-only retention and recorder rate-limit behavior" do
      consume

      expect(context.events.size).to eq(1)
      result = context.events.first.waf_result
      expect(result).not_to be_match
      expect(result).to be_keep
      expect(result.events).to be_empty
      expect(result.actions).to be_empty
      expect(result.attributes).to be_empty
      if retention == :on_record
        expect(trace.sampling_priority).to eq(0)
        allow(Datadog::AppSec::RateLimiter.thread_local).to receive(:limit)
        Datadog::AppSec::Event.record(context)
        expect(trace.sampling_priority).to eq(0)
        allow(Datadog::AppSec::RateLimiter.thread_local).to receive(:limit).and_yield
        Datadog::AppSec::Event.record(context)
      end
      expect(trace.sampling_priority).to eq(2)
      expect(trace.get_tag("_dd.p.dm")).to eq("-5")
      expect(trace.get_tag("_dd.p.ts")).to eq("02")
      expect(context.metrics.waf.matches).to eq(0)
      expect(context.metrics.rasp.matches).to eq(0)
      allow(Datadog::AppSec::RateLimiter.thread_local).to receive(:limit)
      Datadog::AppSec::Event.record(context)
      expect(trace.sampling_priority).to eq(2)
      expect(span.tags).not_to include("appsec.event", "appsec.blocked", "_dd.appsec.json")
    end
  end
end
