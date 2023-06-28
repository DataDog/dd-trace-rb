require 'spec_helper'

require 'datadog/tracing/sampling/rate_limiter'

RSpec.describe Datadog::Tracing::Sampling::TokenBucket do
  subject(:bucket) { described_class.new(rate, max_tokens) }

  let(:rate) { 1 }
  let(:max_tokens) { 10 }

  before do
    allow(Datadog::Core::Utils::Time).to receive(:get_time).and_return(0)
  end

  describe '#initialize' do
    it 'has all tokens available' do
      expect(bucket.available_tokens).to eq(max_tokens)
    end

    context 'with invalid rate' do
      let(:rate) { :bad }

      it 'raises argument error' do
        expect { bucket }.to raise_error(ArgumentError, /bad/)
      end
    end

    context 'with invalid max_tokens' do
      let(:max_tokens) { :bad }

      it 'raises argument error' do
        expect { bucket }.to raise_error(ArgumentError, /bad/)
      end
    end
  end

  describe '#allow?' do
    subject(:allow?) { bucket.allow?(size) }

    let(:size) { 1 }

    context 'with message the same size of or smaller than available tokens' do
      let(:size) { max_tokens }

      it { is_expected.to eq(true) }
    end

    context 'with message larger than available tokens' do
      let(:size) { max_tokens + 1 }

      it { is_expected.to eq(false) }
    end

    context 'after 1 second' do
      before do
        allow(Datadog::Core::Utils::Time).to receive(:get_time).and_return(0, 1)
      end

      it 'does not exceed maximum allowance' do
        expect(bucket.available_tokens).to eq(max_tokens)
      end
    end

    context 'and tokens consumed' do
      before { bucket.allow?(max_tokens) }

      context 'with any message' do
        let(:size) { 1 }

        it { is_expected.to eq(false) }
      end

      context 'after 1 second' do
        before do
          allow(Datadog::Core::Utils::Time).to receive(:get_time).and_return(1)
        end

        context 'with message the same size of or smaller than replenished tokens' do
          let(:size) { rate }

          it { is_expected.to eq(true) }
        end

        context 'with message larger than replenished tokens' do
          let(:size) { rate + 1 }

          it { is_expected.to eq(false) }
        end
      end

      context 'after 10 seconds' do
        let(:size) { 0 } # No-op message, only to force token refilling

        before do
          allow(Datadog::Core::Utils::Time).to receive(:get_time).and_return(10)
        end

        it 'catches up the lost time' do
          allow?
          expect(bucket.available_tokens).to eq(rate * 10)
        end
      end
    end

    context 'with negative rate' do
      let(:rate) { -1 }

      it { is_expected.to eq(true) }
    end

    context 'with zero rate' do
      let(:rate) { 0 }

      it { is_expected.to eq(false) }
    end
  end

  describe '#effective_rate' do
    subject(:effective_rate) { bucket.effective_rate }

    context 'before first message' do
      it { is_expected.to eq(1.0) }
    end

    context 'after checking a message' do
      before { bucket.allow?(size) }

      context 'with a conforming message' do
        let(:size) { max_tokens }

        it { is_expected.to eq(1.0) }

        context 'and one non-conforming message' do
          before { bucket.allow?(max_tokens + 1) }

          it { is_expected.to eq(0.5) }
        end
      end

      context 'with a non-conforming message' do
        let(:size) { max_tokens + 1 }

        it { is_expected.to eq(0.0) }
      end
    end

    context 'after multiple buckets elapse' do
      let(:size) { max_tokens }

      before do
        # get time is called multiple times so we increment it on each call
        # to simulate passage of time
        allow(Datadog::Core::Utils::Time).to receive(:get_time).and_return(0, 2, 4, 6, 8, 10)
      end

      context 'after 2 buckets' do
        before do
          bucket.allow?(max_tokens)
          bucket.allow?(max_tokens + 1)
        end

        it 'computes the average of the last two buckets' do
          is_expected.to eq(0.5)
        end
      end

      context 'after 3 buckets' do
        before do
          bucket.allow?(max_tokens)
          bucket.allow?(max_tokens + 1)
          bucket.allow?(max_tokens + 1)
        end

        it 'computes the average of the last two buckets' do
          is_expected.to eq(0.0)
        end
      end
    end

    context 'with negative rate' do
      let(:rate) { -1 }

      it { is_expected.to eq(1.0) }
    end

    context 'with zero rate' do
      let(:rate) { 0 }

      it { is_expected.to eq(0.0) }
    end
  end
end
