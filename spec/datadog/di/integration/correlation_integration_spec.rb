require "datadog/di/spec_helper"
require "datadog/di"

# Integration tests for coordinated sampling (Datadog::DI::Correlation) wired
# through the real Component, Instrumenter, ProbeManager and notification
# builder. The correlation gate is exercised with real instrumentation; the
# active APM trace is stubbed at the Datadog::Tracing seam the gate and builder
# read from.

class CorrelationIntegrationTestClass
  def alpha
    inner
  end

  def beta
    inner
  end

  def inner
    42
  end

  def loop_n(n)
    n.times { inner }
    n
  end
end

RSpec.describe "Correlation integration" do
  di_test

  let(:diagnostics_transport) do
    double(Datadog::DI::Transport::Diagnostics::Transport)
  end

  let(:input_transport) do
    double(Datadog::DI::Transport::Input::Transport)
  end

  before do
    allow(Datadog::DI::Transport::HTTP).to receive(:diagnostics).and_return(diagnostics_transport)
    allow(Datadog::DI::Transport::HTTP).to receive(:input).and_return(input_transport)
    allow(diagnostics_transport).to receive(:send_diagnostics)
    allow(input_transport).to receive(:send_input)
    allow(Datadog::DI).to receive(:current_component).and_return(component)
  end

  after do
    component.shutdown!
  end

  let(:propagate_all_exceptions) { true }

  let(:settings) do
    Datadog::Core::Configuration::Settings.new.tap do |settings|
      settings.remote.enabled = true
      settings.dynamic_instrumentation.enabled = true
      settings.dynamic_instrumentation.internal.development = true
      settings.dynamic_instrumentation.internal.propagate_all_exceptions = propagate_all_exceptions
    end
  end

  let(:agent_settings) { instance_double_agent_settings_with_stubs }
  let(:logger) { logger_allowing_debug }

  let(:component) do
    Datadog::DI::Component.build(settings, agent_settings, logger).tap do |component|
      raise "Component failed to create - unsuitable environment?" if component.nil?
      component.start!
    end
  end

  let(:probe_manager) { component.probe_manager }

  # Captures every snapshot payload the worker would enqueue.
  let(:snapshots) { [] }

  before do
    allow(diagnostics_transport).to receive(:send_diagnostics)
    allow(component.probe_notifier_worker).to receive(:add_snapshot) do |payload|
      snapshots << payload
    end
  end

  # A capturing (snapshot) probe: coordinated sampling applies to it.
  def method_probe(id, method_name, rate_limit: nil)
    Datadog::DI::Probe.new(id: id, type: :log,
      type_name: "CorrelationIntegrationTestClass", method_name: method_name,
      capture_snapshot: true, rate_limit: rate_limit)
  end

  # A non-capturing (log-only) probe: coordinated sampling does not apply, so
  # it keeps its own per-probe rate limit and is not capped per span.
  def non_capturing_probe(id, method_name, rate_limit: nil)
    Datadog::DI::Probe.new(id: id, type: :log,
      type_name: "CorrelationIntegrationTestClass", method_name: method_name,
      capture_snapshot: false, rate_limit: rate_limit)
  end

  def stub_trace(trace_id, span_id)
    trace = double("trace", id: trace_id)
    span = double("span", id: span_id)
    allow(Datadog::Tracing).to receive(:active_trace).and_return(trace)
    allow(Datadog::Tracing).to receive(:active_span).and_return(span)
  end

  def stub_no_trace
    allow(Datadog::Tracing).to receive(:active_trace).and_return(nil)
    allow(Datadog::Tracing).to receive(:active_span).and_return(nil)
  end

  def flush
    component.probe_notifier_worker.flush
  end

  context "tier 1 (active APM trace)" do
    before { stub_trace("trace-abc", "span-1") }

    it "emits both probes in one trace with the same trace id and source" do
      probe_manager.add_probe(method_probe("p-alpha", "alpha", rate_limit: 5000))
      probe_manager.add_probe(method_probe("p-inner", "inner", rate_limit: 5000))

      CorrelationIntegrationTestClass.new.alpha
      flush

      expect(snapshots.size).to eq(2)
      expect(snapshots.map { |s| s[:"dd.trace_id"] }.uniq).to eq(["trace-abc"])
      expect(snapshots.map { |s| s[:trace_id_source] }.uniq).to eq(["apm"])
    end

    it "drops every probe in the sampling unit when the decision is DROP" do
      # rate_limit 0: the deciding probe's limiter denies, so the whole sampling unit
      # drops regardless of which probe fires first.
      probe_manager.add_probe(method_probe("p-alpha", "alpha", rate_limit: 0))
      probe_manager.add_probe(method_probe("p-inner", "inner", rate_limit: 0))

      CorrelationIntegrationTestClass.new.alpha
      flush

      expect(snapshots).to be_empty
    end

    it "caps a probe to one snapshot per span despite many hits" do
      probe_manager.add_probe(method_probe("p-inner", "inner", rate_limit: 5000))

      CorrelationIntegrationTestClass.new.loop_n(25)
      flush

      expect(snapshots.size).to eq(1)
    end

    it "resets the cap across spans" do
      probe_manager.add_probe(method_probe("p-inner", "inner", rate_limit: 5000))

      stub_trace("trace-abc", "span-1")
      CorrelationIntegrationTestClass.new.inner
      stub_trace("trace-abc", "span-2")
      CorrelationIntegrationTestClass.new.inner
      flush

      expect(snapshots.size).to eq(2)
    end

    it "carries the per-process runtime id on the snapshot" do
      probe_manager.add_probe(method_probe("p-inner", "inner", rate_limit: 5000))

      CorrelationIntegrationTestClass.new.inner
      flush

      expect(snapshots.size).to eq(1)
      expect(snapshots.first[:runtimeId]).to eq(Datadog::Core::Environment::Identity.id)
    end
  end

  context "non-capturing probes" do
    before { stub_trace("trace-abc", "span-1") }

    it "bypasses coordination and is not capped per span" do
      probe_manager.add_probe(non_capturing_probe("p-inner", "inner", rate_limit: 5000))

      CorrelationIntegrationTestClass.new.loop_n(25)
      flush

      expect(snapshots.size).to eq(25)
    end
  end

  context "no active trace" do
    before { stub_no_trace }

    it "makes an independent decision outside any sampling unit" do
      probe_manager.add_probe(method_probe("p-inner", "inner", rate_limit: 5000))

      CorrelationIntegrationTestClass.new.inner
      flush

      expect(snapshots.size).to eq(1)
      expect(snapshots.first[:trace_id_source]).to eq("none")
    end
  end

  context "fail-open" do
    let(:propagate_all_exceptions) { false }

    before { stub_trace("trace-abc", "span-1") }

    it "still emits when the gate raises" do
      probe_manager.add_probe(method_probe("p-inner", "inner", rate_limit: 5000))
      allow(component.correlation).to receive(:emit?).and_raise("gate boom")

      CorrelationIntegrationTestClass.new.inner
      flush

      expect(snapshots.size).to eq(1)
    end
  end
end
