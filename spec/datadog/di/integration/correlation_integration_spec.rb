require "datadog/di/spec_helper"
require "datadog/di"

require_relative "correlation_integration_test_class"

# Integration tests for coordinated sampling (Datadog::DI::CorrelationSampler) wired
# through the real Component, Instrumenter, ProbeManager and notification
# builder. The correlation gate is exercised with real instrumentation; the
# active APM trace is stubbed at the Datadog::Tracing seam the gate reads from.
# The Component builds CorrelationSampler with production limits, ample for
# these examples.

RSpec.describe "Correlation integration" do
  di_test

  let(:diagnostics_transport) do
    instance_double(Datadog::DI::Transport::Diagnostics::Transport)
  end

  let(:input_transport) do
    instance_double(Datadog::DI::Transport::Input::Transport)
  end

  before do
    allow(Datadog::DI::Transport::HTTP).to receive_messages(
      diagnostics: diagnostics_transport,
      input: input_transport,
    )
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

  let(:trace_id) { 123 }
  let(:span_id) { 456 }

  # Captures every snapshot payload the worker would enqueue.
  let(:snapshots) { [] }

  before do
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
  # it keeps its own per-probe rate limit and is not counted per trace.
  def non_capturing_probe(id, method_name, rate_limit: nil)
    Datadog::DI::Probe.new(id: id, type: :log,
      type_name: "CorrelationIntegrationTestClass", method_name: method_name,
      capture_snapshot: false, rate_limit: rate_limit)
  end

  def stub_trace(trace_id, span_id)
    trace = instance_double(Datadog::Tracing::TraceOperation, id: trace_id)
    span = instance_double(Datadog::Tracing::SpanOperation, id: span_id)
    allow(Datadog::Tracing).to receive_messages(active_trace: trace, active_span: span)
  end

  def stub_no_trace
    allow(Datadog::Tracing).to receive_messages(active_trace: nil, active_span: nil)
  end

  def flush
    component.probe_notifier_worker.flush
  end

  context "active APM trace" do
    before { stub_trace(trace_id, span_id) }

    it "emits a nested capturing chain together, sharing the trace id" do
      probe_manager.add_probe(method_probe("p-alpha", "alpha"))
      probe_manager.add_probe(method_probe("p-inner", "inner"))

      CorrelationIntegrationTestClass.new.alpha
      flush

      expect(snapshots.size).to eq(2)
      expect(snapshots.map { |s| s[:"dd.trace_id"] }.uniq).to eq([trace_id.to_s])
    end

    it "bounds one probe to the per-probe counter within a trace" do
      probe_manager.add_probe(method_probe("p-inner", "inner"))

      CorrelationIntegrationTestClass.new.loop_n(25)
      flush

      expect(snapshots.size).to eq(Datadog::DI::CorrelationSampler::PER_PROBE_BUDGET)
    end

    it "carries the per-process runtime id on the snapshot" do
      probe_manager.add_probe(method_probe("p-inner", "inner"))

      CorrelationIntegrationTestClass.new.inner
      flush

      expect(snapshots.size).to eq(1)
      expect(snapshots.first[:runtime_id]).to eq(Datadog::Core::Environment::Identity.id)
    end
  end

  context "non-capturing probes" do
    before { stub_trace(trace_id, span_id) }

    it "bypasses coordination and keeps its own rate limit" do
      probe_manager.add_probe(non_capturing_probe("p-inner", "inner", rate_limit: 5000))

      CorrelationIntegrationTestClass.new.loop_n(25)
      flush

      expect(snapshots.size).to eq(25)
    end
  end

  context "no active trace" do
    before { stub_no_trace }

    it "applies the capturing probe's own rate limit, uncorrelated" do
      probe_manager.add_probe(method_probe("p-inner", "inner"))

      CorrelationIntegrationTestClass.new.loop_n(25)
      flush

      expect(snapshots.size).to eq(1)
    end
  end

  context "fail-open" do
    let(:propagate_all_exceptions) { false }

    before { stub_trace(trace_id, span_id) }

    it "still emits when the gate raises" do
      probe_manager.add_probe(method_probe("p-inner", "inner", rate_limit: 5000))
      expect(component.correlation_sampler).to receive(:emit?).and_raise("gate boom")

      CorrelationIntegrationTestClass.new.inner
      flush

      expect(snapshots.size).to eq(1)
    end
  end

  context "gate raises with propagate_all_exceptions" do
    let(:propagate_all_exceptions) { true }

    before { stub_trace(trace_id, span_id) }

    it "re-raises the gate error to the caller" do
      probe_manager.add_probe(method_probe("p-inner", "inner", rate_limit: 5000))
      allow(component.correlation_sampler).to receive(:emit?).and_raise("gate boom")

      expect { CorrelationIntegrationTestClass.new.inner }.to raise_error(RuntimeError, /gate boom/)
    end
  end

  context "line probe" do
    with_code_tracking

    before do
      stub_trace(trace_id, span_id)
      Object.send(:remove_const, :CorrelationIntegrationTestClass) rescue nil
      load File.join(File.dirname(__FILE__), "correlation_integration_test_class.rb")
    end

    # A capturing line probe routes through the same emit? gate as a method
    # probe, so coordinated sampling bounds it within the trace.
    it "bounds a capturing line probe to the per-probe counter within a trace" do
      probe = Datadog::DI::Probe.new(id: "p-line", type: :log,
        file: "correlation_integration_test_class.rb", line_no: 9,
        capture_snapshot: true)
      probe_manager.add_probe(probe)

      CorrelationIntegrationTestClass.new.loop_n(25)
      flush

      expect(snapshots.size).to eq(Datadog::DI::CorrelationSampler::PER_PROBE_BUDGET)
    end
  end
end
