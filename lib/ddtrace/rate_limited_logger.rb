require 'logger'
require 'ddtrace/logger'

module Datadog
  module RateLimitedLogger
    module Formatter
      def call(severity, timestamp, progname, msg)
        # Do not apply any rate limiting if no rate is configured
        return super unless Datadog.configuration.logging_rate > 0

        # Get the rate limit bucket key
        key = rate_limit_key(severity, progname)

        # Get the currently existing bucket, if one exists
        last_bucket = buckets[key]

        # Get the current time bucket
        # DEV: This is used to determine which logging_rate period this log occurred in
        #   e.g. (1557944138 / 60) = 25965735
        current_time_bucket = timestamp.to_i / Datadog.configuration.logging_rate

        # If we already have an existing time bucket
        unless last_bucket.nil?
          # And we are in the same time bucket as before
          if last_bucket[:time_bucket] == current_time_bucket
            # Increment the skipped count and return (don't log)
            buckets[key][:skipped] += 1
            return
          end
        end

        # Get the previous number of skipped messages to append to message
        skipped_messages = ''
        unless last_bucket.nil? || last_bucket[:skipped].zero?
          skipped_messages = ", #{last_bucket[:skipped]} additional messages skipped"
        end

        # We are in a new time bucket, and are not rate limited
        # Reset the bucket for this key
        buckets[key] = { time_bucket: current_time_bucket,
                         skipped: 0 }

        # Log the message
        super(severity, timestamp, progname, "#{msg}#{skipped_messages}")
      end

      def rate_limit_key(severity, progname)
        @rate_limit_key ||= nil
        return @rate_limit_key unless @rate_limit_key.nil?

        where = ''
        if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.0.0')
          # Skip the first 6
          #   - `Datadop::RateLimitedLogger#rate_limit_key`
          #   - `Datadog::RateLimitedLogger::Formatter#call`
          #   - `::Logger#format_message`
          #   - `Datadog::Logger#add`
          #   - `::Logger#add`
          #   - `::Logger#log` (debug, warn, info, error, etc)
          c = caller_locations(6)
          where = "#{c.first.path}-#{c.first.lineno}-#{c.first.label}-"
        end

        "#{where}#{progname}-#{severity}"
      end

      def rate_limited(key)
        @rate_limit_key ||= key
        yield self
      ensure
        @rate_limit_key ||= nil
      end

      def buckets
        @buckets = @buckets ||= {}
      end
    end

    def self.new(logger = nil)
      logger = logger || Logger.new(STDOUT)
      logger.formatter ||= ::Logger::Formatter.new
      logger.formatter.extend(Formatter)
      logger.extend(self)
    end

    def formatter=(formatter)
      formatter.extend(Formatter)
      super(formatter)
    end

    def rate_limited(key)
      formatter.rate_limited(key) { yield self }
    end

    # private

    # def rate_limit_key(severity, progname, c)
    #   # We want to rate limit key to be as granular as possible to ensure
    #   #   we get one log line per unique message every X seconds
    #   # For example:
    #   #
    #   #     Datadog::Tracer.log.warn('first message')
    #   #     Datadog::Tracer.log.warn('second message')
    #   #
    #   # We want to be sure we always log both log lines every 60 seconds
    #   #   and not just the first message every 60 seconds
    #   # DEV: `c` is `caller` from `#add`, we pass it in so we only need to
    #   #   call `caller` once at most per `#add` call
    #   where = c.length > 1 ? c[1] : ''
    #   "#{where}-#{self.progname}-#{progname}-#{severity}"
    # end
  end
end
