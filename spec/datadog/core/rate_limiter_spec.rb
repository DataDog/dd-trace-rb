require "spec_helper"

require "datadog/core/rate_limiter"

RSpec.describe Datadog::Core::TokenBucket do
  subject(:bucket) { described_class.new(rate, max_tokens) }

  let(:rate) { 1 }
  let(:max_tokens) { 10 }

  before do
    allow(Datadog::Core::Utils::Time).to receive(:get_time).and_return(0)
  end

  describe "#initialize" do
    it "has all tokens available" do
      expect(bucket.available_tokens).to eq(max_tokens)
    end

    context "with invalid rate" do
      let(:rate) { :bad }

      it "raises argument error" do
        expect { bucket }.to raise_error(ArgumentError, /bad/)
      end
    end

    context "with invalid max_tokens" do
      let(:max_tokens) { :bad }

      it "raises argument error" do
        expect { bucket }.to raise_error(ArgumentError, /bad/)
      end
    end
  end

  describe "#allow?" do
    subject(:allow?) { bucket.allow?(size) }

    let(:size) { 1 }

    context "with message the same size of or smaller than available tokens" do
      let(:size) { max_tokens }

      it { is_expected.to eq(true) }
    end

    context "with message larger than available tokens" do
      let(:size) { max_tokens + 1 }

      it { is_expected.to eq(false) }
    end

    context "after 1 second" do
      before do
        allow(Datadog::Core::Utils::Time).to receive(:get_time).and_return(0, 1)
      end

      it "does not exceed maximum allowance" do
        expect(bucket.available_tokens).to eq(max_tokens)
      end
    end

    context "and tokens consumed" do
      before { bucket.allow?(max_tokens) }

      context "with any message" do
        let(:size) { 1 }

        it { is_expected.to eq(false) }
      end

      context "after 1 second" do
        before do
          allow(Datadog::Core::Utils::Time).to receive(:get_time).and_return(1)
        end

        context "with message the same size of or smaller than replenished tokens" do
          let(:size) { rate }

          it { is_expected.to eq(true) }
        end

        context "with message larger than replenished tokens" do
          let(:size) { rate + 1 }

          it { is_expected.to eq(false) }
        end
      end

      context "after 10 seconds" do
        let(:size) { 0 } # No-op message, only to force token refilling

        before do
          allow(Datadog::Core::Utils::Time).to receive(:get_time).and_return(10)
        end

        it "catches up the lost time" do
          allow?
          expect(bucket.available_tokens).to eq(rate * 10)
        end
      end
    end

    context "when size is not given" do
      subject(:allow?) { bucket.allow? }

      context "when tokens are available" do
        it "returns true" do
          is_expected.to be true
        end
      end

      context "when tokens are not available" do
        let(:max_tokens) { 1 }

        before do
          bucket.allow?
        end

        it "returns false" do
          is_expected.to be false
        end
      end
    end

    context "with negative rate" do
      let(:rate) { -1 }

      it { is_expected.to eq(true) }
    end

    context "with zero rate" do
      let(:rate) { 0 }

      it { is_expected.to eq(false) }
    end
  end

  describe "#effective_rate" do
    subject(:effective_rate) { bucket.effective_rate }

    context "before first message" do
      it { is_expected.to eq(1.0) }
    end

    context "after checking a message" do
      before { bucket.allow?(size) }

      context "with a conforming message" do
        let(:size) { max_tokens }

        it { is_expected.to eq(1.0) }

        context "and one non-conforming message" do
          before { bucket.allow?(max_tokens + 1) }

          it { is_expected.to eq(0.5) }
        end
      end

      context "with a non-conforming message" do
        let(:size) { max_tokens + 1 }

        it { is_expected.to eq(0.0) }
      end
    end

    context "after multiple buckets elapse" do
      let(:size) { max_tokens }

      before do
        # get time is called multiple times so we increment it on each call
        # to simulate passage of time
        allow(Datadog::Core::Utils::Time).to receive(:get_time).and_return(0, 2, 4, 6, 8, 10)
      end

      context "after 2 buckets" do
        before do
          bucket.allow?(max_tokens)
          bucket.allow?(max_tokens + 1)
        end

        it "computes the average of the last two buckets" do
          is_expected.to eq(0.5)
        end
      end

      context "after 3 buckets" do
        before do
          bucket.allow?(max_tokens)
          bucket.allow?(max_tokens + 1)
          bucket.allow?(max_tokens + 1)
        end

        it "computes the average of the last two buckets" do
          is_expected.to eq(0.0)
        end
      end
    end

    context "with negative rate" do
      let(:rate) { -1 }

      it { is_expected.to eq(1.0) }
    end

    context "with zero rate" do
      let(:rate) { 0 }

      it { is_expected.to eq(0.0) }
    end
  end
end

RSpec.describe Datadog::Core::BorrowingTokenBucket do
  subject(:bucket) { described_class.new(rate, max_tokens: max_tokens) }

  let(:rate) { 20 }
  let(:max_tokens) { 20 }

  before do
    allow(Datadog::Core::Utils::Time).to receive(:get_time).and_return(0)
  end

  describe "#initialize" do
    it "starts full at max_tokens" do
      expect(bucket.available_tokens).to eq(max_tokens)
      expect(bucket.available?).to be(true)
    end

    context "with invalid rate" do
      let(:rate) { :bad }

      it "raises argument error" do
        expect { bucket }.to raise_error(ArgumentError, /bad/)
      end
    end

    context "with invalid max_tokens" do
      let(:max_tokens) { :bad }

      it "raises argument error" do
        expect { bucket }.to raise_error(ArgumentError, /bad/)
      end
    end
  end

  describe "#consume" do
    it "removes one token by default" do
      bucket.consume
      expect(bucket.available_tokens).to eq(19)
    end

    it "removes the requested size" do
      bucket.consume(size: 5)
      expect(bucket.available_tokens).to eq(15)
    end

    it "drives the balance below zero" do
      25.times { bucket.consume }
      expect(bucket.available_tokens).to eq(-5)
      expect(bucket.available?).to be(false)
    end
  end

  describe "#available?" do
    it "is true while the balance is positive" do
      19.times { bucket.consume }
      expect(bucket.available?).to be(true)
    end

    it "is false once the balance reaches zero" do
      20.times { bucket.consume }
      expect(bucket.available?).to be(false)
    end
  end

  describe "refill" do
    it "recovers a negative balance by rate * elapsed" do
      allow(Datadog::Core::Utils::Time).to receive(:get_time).and_return(0)
      30.times { bucket.consume }
      expect(bucket.available_tokens).to eq(-10)

      allow(Datadog::Core::Utils::Time).to receive(:get_time).and_return(0.5)
      expect(bucket.available?).to be(false)
      expect(bucket.available_tokens).to eq(0)
    end

    it "caps the balance at max_tokens on the upper side" do
      allow(Datadog::Core::Utils::Time).to receive(:get_time).and_return(0)
      bucket.consume
      allow(Datadog::Core::Utils::Time).to receive(:get_time).and_return(100)
      expect(bucket.available?).to be(true)
      expect(bucket.available_tokens).to eq(max_tokens)
    end
  end
end
