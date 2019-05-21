require 'time'

module Datadog
  module Logging
    # Limiter is a helper class for managing log message rate limits
    class Limiter
      def initialize
        reset
      end

      def rate_limited?(key, timestamp = nil)
        # If no logging rate is enabled, then return false, not rate limited
        return false unless Datadog.configuration.logging.rate > 0

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

          # Return true, we are rate limited
          return true
        end

        # We are in a new time bucket, update the latest time bucket
        # DEV: Do not reset `:skipped`, we reset that once we fetch it
        @buckets[key][:time_bucket] = current_time_bucket

        # Return false, not rate limited
        false
      end

      def skipped_count(key)
        bucket = @buckets[key]
        unless bucket.nil? || bucket[:skipped].zero?
          skipped = @buckets[key][:skipped]

          # Reset the skipped count
          @buckets[key][:skipped] = 0

          skipped
        end
      end

      def reset
        @buckets = {}
      end
    end
  end
end
