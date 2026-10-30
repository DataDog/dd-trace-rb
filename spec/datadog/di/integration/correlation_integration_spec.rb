require "datadog/di/spec_helper"
require "datadog/di"

require_relative "correlation_integration_test_class"

# The active APM trace is stubbed at the Datadog::DI.active_trace seam.
# The examples run against the production default sampler and hard-limiter
# limits; the ones that exhaust a process-wide limit freeze the
# rate-limiter clock and drain the production default bucket.

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
      raise "Component failed to create" if component.nil?
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

  def method_probe(id, method_name, capture_snapshot: true, rate_limit: nil, condition: nil)
    Datadog::DI::Probe.new(id: id, type: :log,
      type_name: "CorrelationIntegrationTestClass", method_name: method_name,
      capture_snapshot: capture_snapshot, rate_limit: rate_limit, condition: condition)
  end

  def flush
    component.probe_notifier_worker.flush
  end

  context "active APM trace" do
    before { stub_active_trace(trace_id, span_id: span_id) }

    it "emits a nested capturing chain together, sharing the trace and span ids" do
      probe_manager.add_probe(method_probe("p-alpha", "alpha"))
      probe_manager.add_probe(method_probe("p-inner", "inner"))

      CorrelationIntegrationTestClass.new.alpha
      flush

      expect(snapshots.size).to eq(2)
      expect(snapshots.map { |s| s[:"dd.trace_id"] }.uniq).to eq([trace_id.to_s])
      expect(snapshots.map { |s| s[:"dd.span_id"] }.uniq).to eq([span_id.to_s])
    end

    context "condition evaluation failures" do
      let(:propagate_all_exceptions) { false }

      it "emits the condition-error snapshot while the GLOBAL budget admits" do
        probe_manager.add_probe(method_probe("p-cond", "inner",
          condition: Datadog::DI::EL::Expression.new("(expression)", "undefined_function()")))

        CorrelationIntegrationTestClass.new.inner
        flush

        expect(snapshots.size).to eq(1)
        expect(snapshots[0][:"dd.trace_id"]).to eq(trace_id.to_s)
      end

      it "drops the condition-error snapshot once the GLOBAL budget is exhausted" do
        freeze_rate_limiter_clock

        # Drain GLOBAL with uncorrelated capturing hits, with the probe's
        # own limit raised so GLOBAL is the only bound.
        stub_no_trace
        probe_manager.add_probe(method_probe("p-drain", "inner", rate_limit: 5000))
        CorrelationIntegrationTestClass.new.loop_n(Datadog::DI::CorrelationSampler::GLOBAL_RATE)
        flush
        expect(snapshots.size).to eq(Datadog::DI::CorrelationSampler::GLOBAL_RATE)
        snapshots.clear

        stub_active_trace(trace_id, span_id: span_id)
        probe_manager.add_probe(method_probe("p-cond", "inner",
          condition: Datadog::DI::EL::Expression.new("(expression)", "undefined_function()")))

        CorrelationIntegrationTestClass.new.inner
        flush

        # The condition-error payload shares the process-wide budget with
        # capturing emits, so the exhausted GLOBAL drops it.
        expect(snapshots).to be_empty
      end

      it "drops the condition-error snapshot in a trace the sampler starved" do
        freeze_rate_limiter_clock

        probe_manager.add_probe(method_probe("p-alpha", "alpha"))
        probe_manager.add_probe(method_probe("p-inner", "inner"))

        # One emitting hit per trace consumes TOP; with TOP_RATE traces
        # established, the next trace's capturing hit starves the trace.
        1.upto(Datadog::DI::CorrelationSampler::TOP_RATE) do |trace_index|
          stub_active_trace(trace_index, span_id: span_id)
          CorrelationIntegrationTestClass.new.inner
        end

        starved_trace_id = Datadog::DI::CorrelationSampler::TOP_RATE + 1
        stub_active_trace(starved_trace_id, span_id: span_id)
        probe_manager.add_probe(method_probe("p-cond", "inner",
          condition: Datadog::DI::EL::Expression.new("(expression)", "undefined_function()")))

        # alpha's capturing hit meets the exhausted TOP gate and starves the
        # trace; inner's condition error then meets the starved budget.
        CorrelationIntegrationTestClass.new.alpha
        flush

        expect(snapshots.size).to eq(Datadog::DI::CorrelationSampler::TOP_RATE)
        expect(snapshots.map { |snapshot| snapshot[:"dd.trace_id"] }).to_not include(starved_trace_id.to_s)
      end
    end

    it "starves the next trace's capturing probes once TOP_RATE traces have established units" do
      freeze_rate_limiter_clock

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

    it "keeps an early trace's per-probe cap across a burst of newer traces" do
      probe_manager.add_probe(method_probe("p-inner", "inner", rate_limit: 5000))

      first_trace = instance_double(Datadog::Tracing::TraceOperation, id: 1)
      allow(Datadog::DI).to receive(:active_trace).and_return(first_trace)
      CorrelationIntegrationTestClass.new.inner

      4100.times do |index|
        stub_active_trace(index + 2, span_id: span_id)
        CorrelationIntegrationTestClass.new.inner
      end

      allow(Datadog::DI).to receive(:active_trace).and_return(first_trace)
      CorrelationIntegrationTestClass.new.inner
      flush

      expect(snapshots.count { |s| s[:"dd.trace_id"] == "1" }).to eq(1)
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

    it "shares the process-wide GLOBAL budget with correlated traffic" do
      freeze_rate_limiter_clock

      # The probe's own limit is raised so GLOBAL is the only bound.
      probe_manager.add_probe(method_probe("p-inner", "inner", rate_limit: 5000))

      CorrelationIntegrationTestClass.new.loop_n(20)
      flush

      # GLOBAL is at zero: the uncorrelated loop stops at its process-wide
      # budget.
      stub_active_trace(987)
      CorrelationIntegrationTestClass.new.inner
      flush

      expect(snapshots.size).to eq(20)
    end
  end

  context "trace finishes inside the probed method" do
    it "labels the snapshot with the trace and span captured at admission" do
      trace = instance_double(Datadog::Tracing::TraceOperation, id: 789)
      span = instance_double(Datadog::Tracing::SpanOperation, id: 111)
      # The gate reads the trace once, for its decision and the admission
      # capture; by the time the builder runs, the probed method has finished
      # the trace and no span is active.
      allow(Datadog::DI).to receive(:active_trace).and_return(trace, nil)
      allow(Datadog::DI).to receive(:active_span).and_return(span, nil)

      probe_manager.add_probe(method_probe("p-inner", "inner"))

      CorrelationIntegrationTestClass.new.inner
      flush

      expect(snapshots.size).to eq(1)
      expect(snapshots[0][:"dd.trace_id"]).to eq("789")
      expect(snapshots[0][:"dd.span_id"]).to eq("111")
    end

    it "labels the snapshot with the admission pair when the method starts a new trace" do
      trace = instance_double(Datadog::Tracing::TraceOperation, id: 789)
      span = instance_double(Datadog::Tracing::SpanOperation, id: 111)
      replacement_trace = instance_double(Datadog::Tracing::TraceOperation, id: 999)
      replacement_span = instance_double(Datadog::Tracing::SpanOperation, id: 222)
      # The gate reads trace A once, for its decision and the admission
      # capture; the probed method then starts trace B, whose trace and span
      # are active when the builder runs. The envelope keeps reporting the
      # admission pair, so its trace id and span id describe one trace.
      allow(Datadog::DI).to receive(:active_trace).and_return(trace, replacement_trace)
      allow(Datadog::DI).to receive(:active_span).and_return(span, replacement_span)

      probe_manager.add_probe(method_probe("p-inner", "inner"))

      CorrelationIntegrationTestClass.new.inner
      flush

      expect(snapshots.size).to eq(1)
      expect(snapshots[0][:"dd.trace_id"]).to eq("789")
      expect(snapshots[0][:"dd.span_id"]).to eq("111")
    end
  end

  context "fail-open" do
    let(:propagate_all_exceptions) { false }

    before { stub_active_trace(trace_id, span_id: span_id) }

    it "still emits when the gate raises" do
      probe_manager.add_probe(method_probe("p-inner", "inner", rate_limit: 5000))
      expect(component.correlation_sampler).to receive(:emit_with_reason?).and_raise("gate boom")

      CorrelationIntegrationTestClass.new.inner
      flush

      expect(snapshots.size).to eq(1)
    end

    it "emits from the builder's own trace when the admission capture fails" do
      probe_manager.add_probe(method_probe("p-inner", "inner", rate_limit: 5000))
      # The gate's read and the admission capture both fail; the builder's
      # own read, after the customer method ran, then supplies the envelope.
      reads = 0
      allow(Datadog::DI).to receive(:active_trace) do
        reads += 1
        raise "trace boom" if reads <= 2

        nil
      end

      CorrelationIntegrationTestClass.new.inner
      flush

      expect(snapshots.size).to eq(1)
      expect(snapshots[0][:"dd.trace_id"]).to be_nil
    end
  end

  context "gate raises with propagate_all_exceptions" do
    let(:propagate_all_exceptions) { true }

    before { stub_active_trace(trace_id, span_id: span_id) }

    it "re-raises the gate error to the caller" do
      probe_manager.add_probe(method_probe("p-inner", "inner", rate_limit: 5000))
      expect(component.correlation_sampler).to receive(:emit_with_reason?).and_raise("gate boom")

      expect { CorrelationIntegrationTestClass.new.inner }.to raise_error(RuntimeError, /gate boom/)
    end
  end

  context "line probe" do
    with_code_tracking

    before do
      stub_active_trace(trace_id, span_id: span_id)
      # Line probes can only resolve code that is loaded while code tracking
      # is active. The fixture is loaded here, inside the with_code_tracking
      # around hook, rather than at spec load time, and its class is uniquely
      # named for this context, so no remove_const reload is needed and no
      # stale class or stale iseq leaks into the object space beside the
      # loaded definition.
      load File.join(File.dirname(__FILE__), "correlation_line_probe_test_class.rb")
    end

    it "bounds a capturing line probe to the per-probe counter within a trace" do
      probe = Datadog::DI::Probe.new(id: "p-line", type: :log,
        file: "correlation_line_probe_test_class.rb", line_no: 18,
        capture_snapshot: true, rate_limit: 5000)
      probe_manager.add_probe(probe)

      CorrelationLineProbeTestClass.new.loop_n(25)
      flush

      expect(snapshots.size).to eq(Datadog::DI::CorrelationSampler::PER_PROBE_BUDGET)
    end
  end
end
