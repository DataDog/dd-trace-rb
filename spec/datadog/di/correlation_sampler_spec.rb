require "datadog/di/spec_helper"
require "datadog/di/correlation_sampler"

RSpec.describe Datadog::DI::CorrelationSampler do
  di_test

  subject(:correlation) do
    described_class.new(sweep_threshold: sweep_threshold, top_rate: top_rate,
      global_rate: global_rate, per_probe_budget: per_probe_budget,
      all_budget: all_budget,)
  end

  let(:sweep_threshold) { 4096 }
  let(:top_rate) { 10 }
  let(:global_rate) { 20 }
  let(:per_probe_budget) { 5 }
  let(:all_budget) { 20 }

  # Freeze the clock so the process-wide buckets hold a fixed balance
  # for each example.
  before do
    allow(Datadog::Core::Utils::Time).to receive(:get_time).and_return(0)
  end

  def probe(id, own_rate_limit_allows: true)
    instance_double(Datadog::DI::Probe, id: id,
      own_rate_limit_allows?: own_rate_limit_allows,)
  end

  # A distinct trace object per call, mirroring the tracer's one trace object
  # per trace.
  def trace
    Object.new
  end

  describe "#initialize" do
    it "rejects a sweep_threshold that is not a positive Integer" do
      expect { described_class.new(sweep_threshold: 0) }
        .to raise_error(ArgumentError, /sweep_threshold must be a positive Integer/)
      expect { described_class.new(sweep_threshold: -1) }
        .to raise_error(ArgumentError, /sweep_threshold must be a positive Integer/)
      expect { described_class.new(sweep_threshold: 4096.0) }
        .to raise_error(ArgumentError, /sweep_threshold must be a positive Integer/)
    end

    it "rejects a per_probe_budget that is not a non-negative Integer" do
      expect { described_class.new(per_probe_budget: -1) }
        .to raise_error(ArgumentError, /per_probe_budget must be a non-negative Integer/)
      expect { described_class.new(per_probe_budget: 1.5) }
        .to raise_error(ArgumentError, /per_probe_budget must be a non-negative Integer/)
    end

    it "rejects an all_budget that is not a non-negative Integer" do
      expect { described_class.new(all_budget: -1) }
        .to raise_error(ArgumentError, /all_budget must be a non-negative Integer/)
      expect { described_class.new(all_budget: 2.5) }
        .to raise_error(ArgumentError, /all_budget must be a non-negative Integer/)
    end

    it "accepts a zero budget" do
      expect { described_class.new(all_budget: 0) }.not_to raise_error
    end
  end

  describe "#emit?" do
    context "no active trace" do
      it "admits when the probe's own rate limit allows" do
        expect(correlation.emit?(probe("a"), nil)).to be(true)
      end

      it "drops when the probe's own rate limit denies" do
        expect(correlation.emit?(probe("a", own_rate_limit_allows: false), nil)).to be(false)
      end

      it "defers to the probe's own rate limit across hits" do
        p = probe("a")
        allow(p).to receive(:own_rate_limit_allows?).and_return(true, false)
        expect(correlation.emit?(p, nil)).to be(true)
        expect(correlation.emit?(p, nil)).to be(false)
      end

      it "decides uncorrelated hits independently" do
        p = probe("a")
        expect(correlation.emit?(p, nil)).to be(true)
        expect(correlation.emit?(p, nil)).to be(true)
      end
    end

    context "top probe (first capturing probe in a trace)" do
      it "emits when GLOBAL and TOP admit" do
        expect(correlation.emit?(probe("a"), trace)).to be(true)
      end

      context "when TOP is exhausted" do
        let(:top_rate) { 1 }

        it "starves the trace: the top probe and every correlated probe drop" do
          expect(correlation.emit?(probe("a"), trace)).to be(true)

          second = trace
          expect(correlation.emit?(probe("a"), second)).to be(false)
          expect(correlation.emit?(probe("b"), second)).to be(false)
        end
      end

      context "when GLOBAL is non-positive" do
        let(:global_rate) { 0 }

        it "starves the trace" do
          first = trace
          expect(correlation.emit?(probe("a"), first)).to be(false)
          expect(correlation.emit?(probe("b"), first)).to be(false)
        end
      end

      context "when the seeded budget denies the top probe" do
        let(:all_budget) { 0 }

        it "drops the top probe and starves the trace" do
          first = trace
          expect(correlation.emit?(probe("a"), first)).to be(false)
          expect(correlation.emit?(probe("b"), first)).to be(false)
        end
      end
    end

    context "per-probe counter" do
      let(:per_probe_budget) { 3 }
      let(:all_budget) { 100 }

      it "lets one probe emit exactly per_probe_budget times in a trace" do
        first = trace
        p = probe("a")
        emitted = 6.times.count { correlation.emit?(p, first) }
        expect(emitted).to eq(3)
      end

      it "gives each distinct probe its own per-probe counter" do
        first = trace
        a = probe("a")
        3.times { correlation.emit?(a, first) }
        expect(correlation.emit?(a, first)).to be(false)
        expect(correlation.emit?(probe("b"), first)).to be(true)
      end
    end

    context "all counter" do
      let(:per_probe_budget) { 100 }
      let(:all_budget) { 4 }

      it "lets a trace emit exactly all_budget snapshots across probes" do
        first = trace
        emitted = %w[a b c d e f].count { |id| correlation.emit?(probe(id), first) }
        expect(emitted).to eq(4)
      end
    end

    context "GLOBAL borrowing" do
      let(:global_rate) { 5 }
      let(:per_probe_budget) { 100 }
      let(:all_budget) { 100 }

      it "consumes GLOBAL past zero for correlated probes, then starves new traces" do
        first = trace
        emitted = %w[a b c d e f g h].count { |id| correlation.emit?(probe(id), first) }
        expect(emitted).to eq(8)

        expect(correlation.emit?(probe("a"), trace)).to be(false)
      end
    end

    context "trace lifetime" do
      let(:per_probe_budget) { 1 }
      let(:all_budget) { 100 }
      let(:top_rate) { 100 }
      let(:global_rate) { 100 }

      it "keeps a trace's counters across newer traces" do
        first = trace
        p = probe("a")
        expect(correlation.emit?(p, first)).to be(true)
        expect(correlation.emit?(p, first)).to be(false)

        5000.times { correlation.emit?(probe("b"), trace) }

        expect(correlation.emit?(p, first)).to be(false)
      end

      it "gives a distinct trace object its own unit" do
        first = trace
        expect(correlation.emit?(probe("a"), first)).to be(true)
        expect(correlation.emit?(probe("a"), trace)).to be(true)
        expect(correlation.emit?(probe("a"), first)).to be(false)
      end
    end

    context "starvation persistence" do
      let(:top_rate) { 1 }

      it "keeps a starved trace starved once TOP refills" do
        expect(correlation.emit?(probe("a"), trace)).to be(true)

        starved = trace
        expect(correlation.emit?(probe("a"), starved)).to be(false)

        # TOP refills, so a fresh trace establishes a unit again...
        allow(Datadog::Core::Utils::Time).to receive(:get_time).and_return(1000)
        expect(correlation.emit?(probe("b"), trace)).to be(true)

        # ...while the starved trace keeps dropping without re-querying the
        # gates.
        expect(correlation.emit?(probe("b"), starved)).to be(false)
      end
    end
  end

  describe Datadog::DI::CorrelationSampler::TraceBudgetLedger do
    subject(:ledger) { described_class.new(sweep_threshold) }

    let(:sweep_threshold) { 2 }

    def budget
      Datadog::DI::CorrelationSampler::TraceBudget.new(per_probe_budget: 1, all_budget: 1)
    end

    it "returns the budget stored for the same trace object" do
      first = Object.new
      b = budget
      ledger.store(first, b)
      expect(ledger.fetch(first)).to equal(b)
    end

    it "returns nil for an unknown trace" do
      expect(ledger.fetch(Object.new)).to be_nil
    end

    it "rejects a sweep_threshold that is not a positive Integer" do
      expect { described_class.new(0) }
        .to raise_error(ArgumentError, /sweep_threshold must be a positive Integer/)
      expect { described_class.new(-1) }
        .to raise_error(ArgumentError, /sweep_threshold must be a positive Integer/)
      expect { described_class.new(2.0) }
        .to raise_error(ArgumentError, /sweep_threshold must be a positive Integer/)
    end

    it "keeps live entries beyond any count" do
      10.times { ledger.store(Object.new, budget) }
      expect(ledger.entries.size).to eq(10)
    end

    it "sweeps entries whose trace is gone" do
      retained = Array.new(2) { Object.new }
      retained.each { |trace| ledger.store(trace, budget) }

      # The thread's stack is freed on join, so the traces allocated inside
      # become unreachable and GC.start collects them.
      Thread.new do
        Array.new(2) { Object.new }.each { |trace| ledger.store(trace, budget) }
        nil
      end.join
      GC.start

      5.times { ledger.store(Object.new, budget) }

      # Nine stores minus the two dead entries: seven retained.
      expect(ledger.entries.size).to eq(7)
      expect(retained.all? { |trace| ledger.fetch(trace) }).to be(true)
    end
  end

  describe Datadog::DI::CorrelationSampler::TraceBudget do
    it "consumes one per-probe and one all token together" do
      budget = described_class.new(per_probe_budget: 5, all_budget: 2)
      expect(budget.admit("a")).to be(true)
      expect(budget.all_remaining).to eq(1)
    end

    it "returns false when the all counter is exhausted" do
      budget = described_class.new(per_probe_budget: 5, all_budget: 2)
      2.times { budget.admit("a") }
      expect(budget.admit("a")).to be(false)
    end

    it "returns false when a probe's per-probe counter is exhausted" do
      budget = described_class.new(per_probe_budget: 1, all_budget: 100)
      expect(budget.admit("a")).to be(true)
      expect(budget.admit("a")).to be(false)
    end

    it "defaults an unseen probe's counter to the per-probe limit" do
      budget = described_class.new(per_probe_budget: 5, all_budget: 100)
      expect(budget.admit("unseen")).to be(true)
      expect(budget.all_remaining).to eq(99)
    end

    it "rejects a budget that is not a non-negative Integer" do
      expect { described_class.new(per_probe_budget: -1, all_budget: 20) }
        .to raise_error(ArgumentError, /per_probe_budget must be a non-negative Integer/)
      expect { described_class.new(per_probe_budget: 1.5, all_budget: 20) }
        .to raise_error(ArgumentError, /per_probe_budget must be a non-negative Integer/)
      expect { described_class.new(per_probe_budget: 5, all_budget: -1) }
        .to raise_error(ArgumentError, /all_budget must be a non-negative Integer/)
      expect { described_class.new(per_probe_budget: 5, all_budget: 1.5) }
        .to raise_error(ArgumentError, /all_budget must be a non-negative Integer/)
    end
  end
end
