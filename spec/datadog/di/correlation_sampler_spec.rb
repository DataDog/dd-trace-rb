require "datadog/di/spec_helper"
require "datadog/di/correlation_sampler"

RSpec.describe Datadog::DI::CorrelationSampler do
  di_test

  subject(:correlation) do
    described_class.new(max_entries: max_entries, top_rate: top_rate,
      global_rate: global_rate, per_probe_budget: per_probe_budget,
      all_budget: all_budget,)
  end

  let(:max_entries) { 4096 }
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

  describe "#initialize" do
    it "rejects a max_entries that is not a positive Integer" do
      expect { described_class.new(max_entries: 0) }
        .to raise_error(ArgumentError, /max_entries must be a positive Integer/)
      expect { described_class.new(max_entries: -1) }
        .to raise_error(ArgumentError, /max_entries must be a positive Integer/)
      expect { described_class.new(max_entries: 4096.0) }
        .to raise_error(ArgumentError, /max_entries must be a positive Integer/)
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
        expect(correlation.emit?(probe("a"), 1)).to be(true)
      end

      context "when TOP is exhausted" do
        let(:top_rate) { 1 }

        it "starves the trace: the top probe and every correlated probe drop" do
          expect(correlation.emit?(probe("a"), 1)).to be(true)
          expect(correlation.emit?(probe("a"), 2)).to be(false)
          expect(correlation.emit?(probe("b"), 2)).to be(false)
        end
      end

      context "when GLOBAL is non-positive" do
        let(:global_rate) { 0 }

        it "starves the trace" do
          expect(correlation.emit?(probe("a"), 1)).to be(false)
          expect(correlation.emit?(probe("b"), 1)).to be(false)
        end
      end

      context "when the seeded budget denies the top probe" do
        let(:all_budget) { 0 }

        it "drops the top probe and starves the trace" do
          expect(correlation.emit?(probe("a"), 1)).to be(false)
          expect(correlation.emit?(probe("b"), 1)).to be(false)
        end
      end
    end

    context "per-probe counter" do
      let(:per_probe_budget) { 3 }
      let(:all_budget) { 100 }

      it "lets one probe emit exactly per_probe_budget times in a trace" do
        p = probe("a")
        emitted = 6.times.count { correlation.emit?(p, 1) }
        expect(emitted).to eq(3)
      end

      it "gives each distinct probe its own per-probe counter" do
        a = probe("a")
        3.times { correlation.emit?(a, 1) }
        expect(correlation.emit?(a, 1)).to be(false)
        expect(correlation.emit?(probe("b"), 1)).to be(true)
      end
    end

    context "all counter" do
      let(:per_probe_budget) { 100 }
      let(:all_budget) { 4 }

      it "lets a trace emit exactly all_budget snapshots across probes" do
        emitted = %w[a b c d e f].count { |id| correlation.emit?(probe(id), 1) }
        expect(emitted).to eq(4)
      end
    end

    context "GLOBAL borrowing" do
      let(:global_rate) { 5 }
      let(:per_probe_budget) { 100 }
      let(:all_budget) { 100 }

      it "consumes GLOBAL past zero for correlated probes, then starves new traces" do
        emitted = %w[a b c d e f g h].count { |id| correlation.emit?(probe(id), 1) }
        expect(emitted).to eq(8)

        expect(correlation.emit?(probe("a"), 2)).to be(false)
      end
    end

    context "when the per-trace ledger exceeds max_entries" do
      let(:max_entries) { 2 }
      let(:per_probe_budget) { 1 }
      let(:all_budget) { 100 }
      let(:top_rate) { 100 }
      let(:global_rate) { 100 }

      it "evicts the oldest trace, resetting its counters" do
        p = probe("a")
        expect(correlation.emit?(p, 1)).to be(true)
        expect(correlation.emit?(p, 1)).to be(false)

        correlation.emit?(probe("b"), 2)
        correlation.emit?(probe("c"), 3)

        expect(correlation.emit?(p, 1)).to be(true)
      end
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
