require "spec_helper"

require "datadog/core/borrowing_token_bucket"

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

    include_examples "a refillable bucket validating constructor arguments"

    context "with negative rate" do
      let(:rate) { -1 }

      it "raises argument error" do
        expect { bucket }.to raise_error(ArgumentError, /must not be negative/)
      end
    end

    context "with negative max_tokens" do
      let(:max_tokens) { -1 }

      it "raises argument error" do
        expect { bucket }.to raise_error(ArgumentError, /max_tokens must not be negative/)
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

    it "raises argument error when size is not a number" do
      expect { bucket.consume(size: :bad) }.to raise_error(ArgumentError, /size must be a number/)
    end

    it "raises argument error when size is negative" do
      expect { bucket.consume(size: -1) }.to raise_error(ArgumentError, /size must not be negative/)
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
      30.times { bucket.consume }
      expect(bucket.available_tokens).to eq(-10)

      allow(Datadog::Core::Utils::Time).to receive(:get_time).and_return(0.5)
      expect(bucket.available?).to be(false)
      expect(bucket.available_tokens).to eq(0)
    end

    it "caps the balance at max_tokens on the upper side" do
      bucket.consume
      allow(Datadog::Core::Utils::Time).to receive(:get_time).and_return(100)
      expect(bucket.available?).to be(true)
      expect(bucket.available_tokens).to eq(max_tokens)
    end
  end
end
