require 'time'

module Datadog
  module Logging
    # Limiter is a helper class for managing log message rate limits
    class Limiter
      def initialize
        reset!
      end

      def rate_limit!(key, timestamp = nil, &block)
        # If no logging rate is enabled, then immediately call the provided block, they are not rate limited
        unless Datadog.configuration.logging.rate > 0
          yield nil
          return
        end

        timestamp ||= Time.now

        # Ensure a bucket exists for this key
        @buckets[key] ||= { time_bucket: nil, skipped: 0 }

        # Get the current time bucket
        # DEV: This is used to determine which logging.rate period this log occurred in
        #   e.g. (1557944138 / 60) = 25965735
        current_time_bucket = timestamp.to_i / Datadog.configuration.logging.rate

        # If we are in the same time bucket, rate limit
        if @buckets[key][:time_bucket] == current_time_bucket
          # Increment the skipped count
          @buckets[key][:skipped] += 1

        else
          # Collec the previous skip count
          skipped = nil
          skipped = @buckets[key][:skipped] if @buckets[key][:skipped] > 0

          # We are in a new time bucket, reset the bucket
          @buckets[key][:time_bucket] = current_time_bucket
          @buckets[key][:skipped] = 0

          yield skipped
        end

        # Always return nil
        nil
      end

      def reset!
        @buckets = {}
      end
    end
  end
end
