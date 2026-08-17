require "datadog/di/spec_helper"
require "datadog/di/correlation_sampler"
require "datadog/di/sampling_unit"

RSpec.describe Datadog::DI::CorrelationSampler do
  di_test

  subject(:correlation) do
    described_class.new(max_entries: max_entries, top_rate: top_rate,
      global_rate: global_rate, per_probe_budget: per_probe_budget,
      all_budget: all_budget)
  end

  let(:max_entries) { 4096 }
  let(:top_rate) { 10 }
  let(:global_rate) { 20 }
  let(:per_probe_budget) { 5 }
  let(:all_budget) { 20 }

  # Freeze the clock so the process-wide buckets never refill mid-example.
  before do
    allow(Datadog::Core::Utils::Time).to receive(:get_time).and_return(0)
  end

  # A rate limiter that admits +allow+ times, then denies.
  def limiter(allow:)
    remaining = allow
    double("limiter").tap do |rl|
      allow(rl).to receive(:allow?) do
        if remaining > 0
          remaining -= 1
          true
        else
          false
        end
      end
    end
  end

  def probe(id, rate_limiter: nil)
    double("probe", id: id, rate_limiter: rate_limiter)
  end

  def unit(key)
    Datadog::DI::SamplingUnit.new(key)
  end

  def none
    Datadog::DI::SamplingUnit.new(nil)
  end

  describe "#emit?" do
    context "no active trace" do
      it "admits a probe with no rate limiter" do
        expect(correlation.emit?(probe("a"), none)).to be(true)
      end

      it "drops when the probe's own rate limiter denies" do
        expect(correlation.emit?(probe("a", rate_limiter: limiter(allow: 0)), none)).to be(false)
      end

      it "defers to the probe's rate limiter across hits" do
        p = probe("a", rate_limiter: limiter(allow: 1))
        expect(correlation.emit?(p, none)).to be(true)
        expect(correlation.emit?(p, none)).to be(false)
      end

      it "does not coordinate independent hits" do
        p = probe("a", rate_limiter: limiter(allow: 2))
        expect(correlation.emit?(p, none)).to be(true)
        expect(correlation.emit?(p, none)).to be(true)
      end
    end

    context "top probe (first capturing probe in a trace)" do
      it "emits when GLOBAL and TOP admit" do
        expect(correlation.emit?(probe("a"), unit(1))).to be(true)
      end

      context "when TOP is exhausted" do
        let(:top_rate) { 1 }

        it "starves the trace: the top probe and every correlated probe drop" do
          # trace 1's top probe consumes the only TOP token.
          expect(correlation.emit?(probe("a"), unit(1))).to be(true)

          # trace 2's top probe finds TOP empty and marks the trace starved.
          expect(correlation.emit?(probe("a"), unit(2))).to be(false)
          # a correlated probe in the starved trace also drops.
          expect(correlation.emit?(probe("b"), unit(2))).to be(false)
        end
      end

      context "when GLOBAL is non-positive" do
        let(:global_rate) { 0 }

        it "starves the trace" do
          expect(correlation.emit?(probe("a"), unit(1))).to be(false)
          expect(correlation.emit?(probe("b"), unit(1))).to be(false)
        end
      end
    end

    context "per-probe counter" do
      let(:per_probe_budget) { 3 }
      let(:all_budget) { 100 }

      it "lets one probe emit exactly per_probe_budget times in a trace" do
        p = probe("a")
        emitted = 6.times.count { correlation.emit?(p, unit(1)) }
        expect(emitted).to eq(3)
      end

      it "gives each distinct probe its own per-probe counter" do
        a = probe("a")
        3.times { correlation.emit?(a, unit(1)) } # exhausts a
        expect(correlation.emit?(a, unit(1))).to be(false)
        expect(correlation.emit?(probe("b"), unit(1))).to be(true)
      end
    end

    context "all counter" do
      let(:per_probe_budget) { 100 }
      let(:all_budget) { 4 }

      it "lets a trace emit exactly all_budget snapshots across probes" do
        emitted = %w[a b c d e f].count { |id| correlation.emit?(probe(id), unit(1)) }
        expect(emitted).to eq(4)
      end
    end

    context "GLOBAL borrowing" do
      let(:global_rate) { 5 }
      let(:per_probe_budget) { 100 }
      let(:all_budget) { 100 }

      it "consumes GLOBAL past zero for correlated probes, then starves new traces" do
        # 8 emits in trace 1 (1 top + 7 correlated) drive GLOBAL from 5 to -3;
        # correlated probes consume GLOBAL without checking it.
        emitted = %w[a b c d e f g h].count { |id| correlation.emit?(probe(id), unit(1)) }
        expect(emitted).to eq(8)

        # GLOBAL is negative, so a new trace's top probe is starved.
        expect(correlation.emit?(probe("a"), unit(2))).to be(false)
      end
    end

    describe "per-trace ledger LRU eviction" do
      let(:max_entries) { 2 }
      let(:per_probe_budget) { 1 }
      let(:all_budget) { 100 }
      let(:top_rate) { 100 }
      let(:global_rate) { 100 }

      it "evicts the oldest trace, resetting its counters" do
        p = probe("a")
        expect(correlation.emit?(p, unit(1))).to be(true)  # top, per-probe → 0
        expect(correlation.emit?(p, unit(1))).to be(false) # capped in trace 1

        correlation.emit?(probe("b"), unit(2)) # ledger: {1, 2}
        correlation.emit?(probe("c"), unit(3)) # inserting 3 evicts oldest (1)

        # trace 1 was evicted, so its counters reset and a emits again as a top.
        expect(correlation.emit?(p, unit(1))).to be(true)
      end
    end
  end

  describe Datadog::DI::CorrelationSampler::TraceBudget do
    it "consumes one per-probe and one all token together" do
      budget = described_class.new(2, 5)
      expect(budget.admit("a")).to be(true)
      expect(budget.all_remaining).to eq(1)
    end

    it "returns false when the all counter is exhausted" do
      budget = described_class.new(2, 5)
      2.times { budget.admit("a") }
      expect(budget.admit("a")).to be(false)
    end

    it "returns false when a probe's per-probe counter is exhausted" do
      budget = described_class.new(100, 1)
      expect(budget.admit("a")).to be(true)
      expect(budget.admit("a")).to be(false)
    end

    it "defaults an unseen probe's counter to the per-probe limit" do
      budget = described_class.new(100, 5)
      expect(budget.admit("unseen")).to be(true)
      expect(budget.all_remaining).to eq(99)
    end
  end
end
