require "datadog/di/spec_helper"
require "datadog/di"

require_relative "correlation_integration_test_class"

# The active APM trace is stubbed at the Datadog::DI.active_trace seam.
# Production sampler limits are ample for these examples.

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
      raise "Component failed to create; see the DI log entries for the reason" if component.nil?
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

  def method_probe(id, method_name, capture_snapshot: true, rate_limit: nil)
    Datadog::DI::Probe.new(id: id, type: :log,
      type_name: "CorrelationIntegrationTestClass", method_name: method_name,
      capture_snapshot: capture_snapshot, rate_limit: rate_limit,)
  end

  def flush
    component.probe_notifier_worker.flush
  end

  context "active APM trace" do
    before { stub_active_trace(trace_id, span_id: span_id) }

    it "emits a nested capturing chain together, sharing the trace id" do
      probe_manager.add_probe(method_probe("p-alpha", "alpha"))
      probe_manager.add_probe(method_probe("p-inner", "inner"))

      CorrelationIntegrationTestClass.new.alpha
      flush

      expect(snapshots.size).to eq(2)
      expect(snapshots.map { |s| s[:"dd.trace_id"] }.uniq).to eq([trace_id.to_s])
    end

    context "with the process-wide hard snapshot limiter exhausted" do
      before do
        # Freeze the rate limiter clock so the drain below is deterministic.
        frozen_time = Datadog::Core::Utils::Time.get_time
        allow(Datadog::Core::Utils::Time).to receive(:get_time).and_return(frozen_time)

        Datadog::DI::Instrumenter::GLOBAL_SNAPSHOT_RATE_LIMIT.times do
          component.instrumenter.global_snapshot_rate_limiter.allow?
        end
        expect(component.instrumenter.global_snapshot_rate_limiter.allow?).to be(false)
      end

      it "emits a nested capturing chain past an exhausted hard snapshot limit" do
        probe_manager.add_probe(method_probe("p-alpha", "alpha"))
        probe_manager.add_probe(method_probe("p-inner", "inner"))

        CorrelationIntegrationTestClass.new.alpha
        flush

        expect(snapshots.size).to eq(2)
        expect(snapshots.map { |s| s[:"dd.trace_id"] }.uniq).to eq([trace_id.to_s])
      end
    end

    it "starves the next trace's capturing probes once TOP_RATE traces have established units" do
      # Freeze the time provider so the process-wide TOP bucket does not
      # refill while this example drives its traces.
      frozen_time = Datadog::Core::Utils::Time.get_time
      allow(Datadog::Core::Utils::Time).to receive(:get_time).and_return(frozen_time)

      probe_manager.add_probe(method_probe("p-inner", "inner"))
      probe_manager.add_probe(method_probe("p-alpha", "alpha"))

      # One emit per trace keeps GLOBAL positive, so TOP is the gate the
      # starved trace fails.
      1.upto(Datadog::DI::CorrelationSampler::TOP_RATE) do |trace_index|
        stub_active_trace(trace_index, span_id: span_id)
        CorrelationIntegrationTestClass.new.inner
      end

      starved_trace_id = Datadog::DI::CorrelationSampler::TOP_RATE + 1
      stub_active_trace(starved_trace_id, span_id: span_id)
      CorrelationIntegrationTestClass.new.alpha
      flush

      expect(snapshots.size).to eq(Datadog::DI::CorrelationSampler::TOP_RATE)
      expect(snapshots.map { |snapshot| snapshot[:"dd.trace_id"] }).to_not include(starved_trace_id.to_s)
    end

    it "bounds one probe to the per-probe counter within a trace" do
      probe_manager.add_probe(method_probe("p-inner", "inner", rate_limit: 5000))

      CorrelationIntegrationTestClass.new.loop_n(25)
      flush

      expect(snapshots.size).to eq(Datadog::DI::CorrelationSampler::PER_PROBE_BUDGET)
    end

    it "emits a correlated hit with the probe's own rate limit at zero" do
      probe_manager.add_probe(method_probe("p-inner", "inner", rate_limit: 0))

      CorrelationIntegrationTestClass.new.inner
      flush

      expect(snapshots.size).to eq(1)
    end

    it "carries the per-process runtime id on the snapshot" do
      fake_runtime_id = "123e4567-e89b-12d3-a456-426614174000"
      allow(Datadog::Core::Environment::Identity).to receive(:id).and_return(fake_runtime_id)

      probe_manager.add_probe(method_probe("p-inner", "inner"))

      CorrelationIntegrationTestClass.new.inner
      flush

      expect(snapshots.size).to eq(1)
      expect(snapshots.first[:runtime_id]).to eq(fake_runtime_id)
    end
  end

  context "non-capturing probes" do
    before { stub_active_trace(trace_id, span_id: span_id) }

    it "bypasses coordination and keeps its own rate limit" do
      probe_manager.add_probe(method_probe("p-inner", "inner", capture_snapshot: false, rate_limit: 5000))

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

    before { stub_active_trace(trace_id, span_id: span_id) }

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

    before { stub_active_trace(trace_id, span_id: span_id) }

    it "re-raises the gate error to the caller" do
      probe_manager.add_probe(method_probe("p-inner", "inner", rate_limit: 5000))
      expect(component.correlation_sampler).to receive(:emit?).and_raise("gate boom")

      expect { CorrelationIntegrationTestClass.new.inner }.to raise_error(RuntimeError, /gate boom/)
    end
  end

  context "line probe" do
    with_code_tracking

    before do
      stub_active_trace(trace_id, span_id: span_id)
      # Line probes can only resolve code that is loaded while code tracking
      # is active. The fixture class was already required at spec load time,
      # before `with_code_tracking` activated tracking for this example, so
      # remove the constant and load the fixture again to make line 13
      # trackable by the probe below.
      if Object.const_defined?(:CorrelationIntegrationTestClass)
        Object.send(:remove_const, :CorrelationIntegrationTestClass)
      end
      load File.join(File.dirname(__FILE__), "correlation_integration_test_class.rb")
    end

    it "bounds a capturing line probe to the per-probe counter within a trace" do
      probe = Datadog::DI::Probe.new(id: "p-line", type: :log,
        file: "correlation_integration_test_class.rb", line_no: 13,
        capture_snapshot: true, rate_limit: 5000,)
      probe_manager.add_probe(probe)

      CorrelationIntegrationTestClass.new.loop_n(25)
      flush

      expect(snapshots.size).to eq(Datadog::DI::CorrelationSampler::PER_PROBE_BUDGET)
    end
  end
end
