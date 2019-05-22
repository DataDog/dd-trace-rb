require 'spec_helper'

require 'ddtrace'

RSpec.describe Datadog::Logging::Limiter do
  subject(:limiter) { described_class.new }
  after(:each) { limiter.reset! }
  let(:key) { 'unique-key' }

  def rate_limit_expected
    expect { |b| limiter.rate_limit!(key, &b) }
  end

  def is_not_rate_limited
    rate_limit_expected.to yield_control.once
  end

  def is_rate_limited
    rate_limit_expected.to_not yield_control
  end

  def receives_skipped_count(count)
    rate_limit_expected.to yield_with_args(count)
  end

  describe '#rate_limit!' do
    context 'calling once' do
      context 'is not rate limited' do
        # Does not get rate limited
        it { is_not_rate_limited }
        # Does not have a skipped count
        it { receives_skipped_count(nil) }
      end
    end

    context 'calling multiple times' do
      context 'in the same time period' do
        it do
          # Freeze time to stay in the same bucket
          Timecop.freeze do
            # First time is not rate limited
            is_not_rate_limited

            # All future calls are rate limited
            5.times do
              is_rate_limited
            end
          end
        end
      end

      context 'in different time periods' do
        it do
          # Freeze time
          Timecop.freeze do
            # First time is not rate limited
            is_not_rate_limited

            # Travel 5 minutes into the future
            Timecop.travel(Time.now + 300)

            # Second time is not rate limited
            is_not_rate_limited
          end
        end
      end

      context 'logging rate of 0' do
          let(:rate) { 0 }
          before(:each) { allow(Datadog.configuration.logging).to receive(:rate).and_return(rate) }

          context 'we never rate limit' do
            let(:start) { Time.now }

            it do
              Timecop.freeze(start) do
                300.times do |i|
                  # We are never rate limited
                  is_not_rate_limited

                  Timecop.travel(start + i)
                end
              end
            end
          end
      end

      [
        # The default
        Datadog.configuration.logging.rate,

        1,
        5,
        10,
        20,
        30,
        60,
        120,
      ].each do |value|
        context "logging rate of #{value}" do
          let(:rate) { value }
          before(:each) { allow(Datadog.configuration.logging).to receive(:rate).and_return(rate) }

          let(:start) do
            # Get current time bucket
            bucket = Time.now.to_i / Datadog.configuration.logging.rate

            # Convert back to time
            Time.at(bucket * Datadog.configuration.logging.rate)
          end

          context 'one second before start' do
            it do
              # Freeze time one second before bucket start
              Timecop.freeze(start - 1) do
                # Not rate limited
                is_not_rate_limited

                # Advance time to start
                Timecop.travel(start)

                # Not rate limited
                is_not_rate_limited
              end
            end
          end

          context 'duration of period' do
            it do
              # Freeze time at beginning of period
              Timecop.freeze(start) do
                # Not rate limited
                is_not_rate_limited

                # For every second contained in this period (rate-1 to get us up until the next period)
                (Datadog.configuration.logging.rate - 1).times do |i|
                  Timecop.travel(start + i)

                  # Rate limited
                  is_rate_limited
                end
              end
            end
          end

          context 'next period' do
            it do
              # Freeze time at beginning of period
              Timecop.freeze(start) do
                # Not rate limited
                is_not_rate_limited

                # Increment to one second before the next period, rate limited
                Timecop.travel(start + Datadog.configuration.logging.rate - 1)
                is_rate_limited

                # Increment to the start of the next period, not rate limited
                Timecop.travel(start + Datadog.configuration.logging.rate)
                is_not_rate_limited
              end
            end
          end
        end
      end
    end

    context 'skipped count' do
      context 'first call' do
        it { receives_skipped_count(nil) }
      end

      # This is the typical workflow
      context 'after being reset' do
        it do
          # Freeze time to ensure we are in the same time bucket
          Timecop.freeze do
            # First call is not rate limited and receives no skipped count
            receives_skipped_count(nil)

            # Call 5 more times when rate limited
            5.times { is_rate_limited }

            # Skip ahead by 5 minutes so we are in a new time bucket
            Timecop.travel(Time.now + 300)

            # We are not rate limited and receive a skipped count of 5
            receives_skipped_count(5)
          end
        end
      end
    end
  end

  context '#reset' do
    context 'resets the buckets' do
      it do
        # Freeze time to ensure we stay in the same time bucket
        Timecop.freeze do
          # First is not rate limited
          is_not_rate_limited

          # Second is rate limited
          is_rate_limited

          # Reset the buckets
          limiter.reset!

          # No longer rate limited
          is_not_rate_limited

          # Second is rate limited
          is_rate_limited
        end
      end
    end
  end
end
