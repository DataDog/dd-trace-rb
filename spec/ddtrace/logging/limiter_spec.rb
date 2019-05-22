require 'spec_helper'

require 'ddtrace'

RSpec.describe Datadog::Logging::Limiter do
  subject(:limiter) { described_class.new }
  after(:each) { limiter.reset! }
  let(:key) { 'unique-key' }

  context '#rate_limited?' do
    context 'calling once' do
      context 'is not rate limited' do
        # Does not get rate limited
        it { expect(limiter.rate_limited?(key)).to be(false) }
      end
    end

    context 'calling multiple times' do
      context 'in the same time period' do
        it do
          # Freeze time to stay in the same bucket
          Timecop.freeze do
            # First time is not rate limited
            expect(limiter.rate_limited?(key)).to be(false)

            # All future calls is rate limited
            5.times do
              expect(limiter.rate_limited?(key)).to be(true)
            end
          end
        end
      end

      context 'in different time periods' do
        it do
          # Freeze time
          Timecop.freeze do
            # First time is not rate limited
            expect(limiter.rate_limited?(key)).to be(false)

            # Travel 5 minutes into the future
            Timecop.travel(Time.now + 300)

            # Second time is not rate limited
            expect(limiter.rate_limited?(key)).to be(false)
          end
        end
      end

      context 'boundaries' do
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
              expect(limiter.rate_limited?(key)).to be(false)

              # Advance time to start
              Timecop.travel(start)

              # Not rate limited
              expect(limiter.rate_limited?(key)).to be(false)
            end
          end
        end

        context 'duration of period' do
          it do
            # Freeze time at beginning of period
            Timecop.freeze(start) do
              # Not rate limited
              expect(limiter.rate_limited?(key)).to be(false)

              # For every second contained in this period (rate-1 to get us up until the next period)
              (Datadog.configuration.logging.rate - 1).times do |i|
                Timecop.travel(start + i)

                # Rate limited
                expect(limiter.rate_limited?(key)).to be(true)
              end
            end
          end
        end

        context 'next period' do
          it do
            # Freeze time at beginning of period
            Timecop.freeze(start) do
              # Not rate limited
              expect(limiter.rate_limited?(key)).to be(false)

              # Increment to one second before the next period, rate limited
              Timecop.travel(start + Datadog.configuration.logging.rate - 1)
              expect(limiter.rate_limited?(key)).to be(true)

              # Increment to the start of the next period, not rate limited
              Timecop.travel(start + Datadog.configuration.logging.rate)
              expect(limiter.rate_limited?(key)).to be(false)
            end
          end
        end
      end
    end
  end

  context '#skipped_count' do
    subject(:skipped_count) { limiter.skipped_count(key) }

    context 'with unknown key' do
      it { is_expected.to be_nil }
    end

    context 'after first call' do
      # DEV: No reason to freeze time, only calling this once
      before(:each) { limiter.rate_limited?(key) }

      it { is_expected.to be_nil }
    end

    context 'after multiple calls' do
      before(:each) do
        # Freeze time to ensure we are in the same time bucket
        Timecop.freeze do
          5.times { limiter.rate_limited?(key) }
        end
      end

      it do
        # Contains the count of items rate limited
        is_expected.to eq(4)

        # After a successful call to `#skipped_count` we reset the count

        expect(limiter.skipped_count(key)).to be_nil
      end
    end

    context 'after being reset' do
      it do
        # Freeze time to ensure we stay in the same time bucket
        Timecop.freeze do
          # Check rate limit 5 times
          5.times { limiter.rate_limited?(key) }

          # Skip time ahead 5 minutes (new time bucket)
          Timecop.travel(Time.now + 300)

          # DEV: This is the typical workflow, check if you are rate limited,
          #   if not, immediately fetch (and reset) the skipped count

          # Check rate limit again
          expect(limiter.rate_limited?(key)).to be(false)

          # Check the skipped count, should be the count from the previous bucket
          expect(limiter.skipped_count(key)).to eq(4)
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
          expect(limiter.rate_limited?(key)).to be(false)

          # Second is rate limited
          expect(limiter.rate_limited?(key)).to be(true)

          # Reset the buckets
          limiter.reset!

          # No longer rate limited
          expect(limiter.rate_limited?(key)).to be(false)

          # Second is rate limited
          expect(limiter.rate_limited?(key)).to be(true)
        end
      end
    end
  end
end
