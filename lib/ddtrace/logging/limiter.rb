require 'time'

module Datadog
  module Logging
    class Limiter
      def initialize()
        @buckets = {}
      end

      def rate_limited?(key, timestamp = nil)
        # If no logging rate is enabled, then return false, not rate limited
        return false unless Datadog.configuration.logging.rate > 0

        timestamp ||= Time.now

        # Get the currently existing bucket, if one exists
        last_bucket = @buckets[key]

        # Get the current time bucket
        # DEV: This is used to determine which logging.rate period this log occurred in
        #   e.g. (1557944138 / 60) = 25965735
        current_time_bucket = timestamp.to_i / Datadog.configuration.logging.rate

        # If we already have an existing time bucket
        unless last_bucket.nil?
          # And we are in the same time bucket as before
          if last_bucket[:time_bucket] == current_time_bucket
            # Increment the skipped count
            @buckets[key][:skipped] += 1

            # Return true, we are rate limited
            return true
          end
        end

        # We are in a new time bucket
        # Reset the bucket for this key
        @buckets[key] ||= { time_bucket: nil,
                           skipped: 0 }

        @buckets[key][:time_bucket] = current_time_bucket
        # Return false, not rate limited
        return false
      end

      def skipped_count(key)
        bucket = @buckets[key]
        unless bucket.nil? || bucket[:skipped].zero?
          skipped = @buckets[key][:skipped]

          # Reset the skipped count
          @buckets[key][:skipped]

          skipped
        end
      end
    end
  end
end
