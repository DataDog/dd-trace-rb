require "datadog/di/spec_helper"
require "datadog/di/correlation"

RSpec.describe Datadog::DI::Correlation do
  di_test

  let(:settings) { double("settings") }
  let(:logger) { double("logger").tap { |l| allow(l).to receive(:debug) } }

  subject(:correlation) { described_class.new(settings, logger, max_entries: max_entries) }

  let(:max_entries) { 4096 }

  # A probe whose rate limiter admits +allow+ times, then denies. nil limiter
  # means "always allow" (matches a probe constructed with no rate limit).
  def probe_double(id, allow: Float::INFINITY, limiter: :default)
    rate_limiter =
      if limiter == :default
        remaining = allow
        double("rate_limiter").tap do |rl|
          allow(rl).to receive(:allow?) do
            if remaining > 0
              remaining -= 1
              true
            else
              false
            end
          end
        end
      else
        limiter
      end
    double("probe", id: id, rate_limiter: rate_limiter)
  end

  def stub_active_trace(trace_id, span_id: nil)
    trace = double("trace", id: trace_id)
    span = span_id && double("span", id: span_id)
    allow(Datadog::Tracing).to receive(:active_trace).and_return(trace)
    allow(Datadog::Tracing).to receive(:active_span).and_return(span)
  end

  def stub_no_trace
    allow(Datadog::Tracing).to receive(:active_trace).and_return(nil)
    allow(Datadog::Tracing).to receive(:active_span).and_return(nil)
  end

  before { correlation.end_unit }
  after { correlation.end_unit }

  describe "#gate" do
    context "tier 1 (active APM trace)" do
      before { stub_active_trace("trace-1", span_id: "span-1") }

      it "emits when the deciding probe's limiter admits" do
        expect(correlation.gate(probe_double("a", allow: 1))).to eq(:emit)
      end

      it "drops the whole unit when the deciding probe's limiter denies" do
        expect(correlation.gate(probe_double("a", allow: 0))).to eq(:drop)
      end

      it "shares one decision across sibling probes in the same trace" do
        # First probe decides EMIT for the unit.
        expect(correlation.gate(probe_double("a", allow: 1))).to eq(:emit)
        # Sibling probe with a denying limiter still inherits EMIT (its limiter
        # is not consulted), then emits once under its own cap slot.
        sibling = probe_double("b", allow: 0)
        expect(correlation.gate(sibling)).to eq(:emit)
      end

      it "propagates a DROP decision to sibling probes" do
        expect(correlation.gate(probe_double("a", allow: 0))).to eq(:drop)
        # Sibling whose own limiter would admit still inherits DROP.
        expect(correlation.gate(probe_double("b", allow: 1))).to eq(:drop)
      end

      describe "per-probe-per-span cap" do
        it "admits a probe once per span, then suppresses repeats" do
          probe = probe_double("a", allow: 5)
          expect(correlation.gate(probe)).to eq(:emit)
          expect(correlation.gate(probe)).to eq(:drop) # capped
          expect(correlation.gate(probe)).to eq(:drop) # capped
        end

        it "does not let one probe's cap affect another probe" do
          correlation.gate(probe_double("a", allow: 1)) # decides EMIT for unit
          expect(correlation.gate(probe_double("a", allow: 5))).to eq(:drop) # a capped
          expect(correlation.gate(probe_double("b", allow: 5))).to eq(:emit) # b fresh
        end

        it "resets the cap for a different span" do
          probe = probe_double("a", allow: 5)
          stub_active_trace("trace-1", span_id: "span-1")
          expect(correlation.gate(probe)).to eq(:emit)
          expect(correlation.gate(probe)).to eq(:drop)
          stub_active_trace("trace-1", span_id: "span-2")
          expect(correlation.gate(probe)).to eq(:emit)
        end
      end
    end

    context "tier 2 (task context, no active trace)" do
      before { stub_no_trace }

      it "shares one decision within a unit and resets across units" do
        correlation.begin_unit("task-1")
        expect(correlation.gate(probe_double("a", allow: 1))).to eq(:emit)
        expect(correlation.gate(probe_double("b", allow: 0))).to eq(:emit) # inherits

        correlation.begin_unit("task-2")
        # New unit makes an independent decision.
        expect(correlation.gate(probe_double("a", allow: 0))).to eq(:drop)
      end

      it "caps a probe once per task unit" do
        correlation.begin_unit("task-1")
        probe = probe_double("a", allow: 5)
        expect(correlation.gate(probe)).to eq(:emit)
        expect(correlation.gate(probe)).to eq(:drop)
      end
    end

    context "no execution unit" do
      before do
        stub_no_trace
        correlation.end_unit
      end

      it "makes an independent per-probe decision" do
        expect(correlation.gate(probe_double("a", allow: 1))).to eq(:emit)
        expect(correlation.gate(probe_double("a", allow: 0))).to eq(:drop)
      end

      it "does not cache decisions across independent hits" do
        # Same probe, its limiter admits twice: both independent hits emit
        # (no unit to coordinate).
        probe = probe_double("a", allow: 2)
        expect(correlation.gate(probe)).to eq(:emit)
        expect(correlation.gate(probe)).to eq(:emit)
      end
    end

    describe "cap-scope LRU eviction" do
      let(:max_entries) { 2 }

      it "evicts the oldest cap scope, resetting its cap" do
        probe = probe_double("a", allow: 100)
        stub_active_trace("t", span_id: "s1")
        expect(correlation.gate(probe)).to eq(:emit)
        expect(correlation.gate(probe)).to eq(:drop) # s1 caps a

        stub_active_trace("t", span_id: "s2")
        correlation.gate(probe)
        stub_active_trace("t", span_id: "s3")
        correlation.gate(probe) # inserting s3 evicts s1

        stub_active_trace("t", span_id: "s1")
        # s1 was evicted, so its cap has reset and a may emit again.
        expect(correlation.gate(probe)).to eq(:emit)
      end
    end

    describe "observable state" do
      before { stub_active_trace("trace-1", span_id: "span-1") }

      it "counts decisions and records the last decision time" do
        expect(correlation.decisions_made).to eq(0)
        expect(correlation.last_decision_at).to be_nil
        correlation.gate(probe_double("a", allow: 1))
        expect(correlation.decisions_made).to eq(1)
        expect(correlation.last_decision_at).to be_a(Time)
      end
    end
  end

  describe "#with_unit" do
    before { stub_no_trace }

    it "sets a correlation id for the block and restores the previous value" do
      expect(Thread.current[described_class::TIER2_KEY]).to be_nil
      correlation.with_unit("task-x") do
        expect(Thread.current[described_class::TIER2_KEY]).to eq("task-x")
      end
      expect(Thread.current[described_class::TIER2_KEY]).to be_nil
    end

    it "generates a UUID when no id is given" do
      correlation.with_unit do
        expect(Thread.current[described_class::TIER2_KEY]).to match(/\A[0-9a-f-]{36}\z/)
      end
    end

    it "restores the previous value even when the block raises" do
      correlation.begin_unit("outer")
      expect do
        correlation.with_unit("inner") { raise "boom" }
      end.to raise_error("boom")
      expect(Thread.current[described_class::TIER2_KEY]).to eq("outer")
    end
  end
end
