require 'logger'
require 'ddtrace/logging/logger'
require 'ddtrace/logging/limiter'

module Datadog
  module Logging
    # Logger rate limiter used to limit the number of log messages emitted in a given period
    class RateLimitedLogger < Logger
      # Custom formatter used to rate limit log messages
      module Formatter
        def call(severity, timestamp, progname, msg)
          # Do not apply any rate limiting if no rate is configured
          return super unless Datadog.configuration.logging.rate > 0

          # Get the key we should use for rate limiting
          key = rate_limit_key(severity, progname)

          # Return early if we were rate limited
          return if Datadog::Tracer.log_limiter.rate_limited?(key, timestamp = timestamp)

          # Append skipped count if we have one
          # DEV: `skipped_msgs` will be > 0 or nil (never 0)
          skipped_msgs = Datadog::Tracer.log_limiter.skipped_count(key)
          if skipped_msgs
            msg = "#{msg}, #{skipped_msgs} additional messages skipped"
          end

          # Log the message
          super(severity, timestamp, progname, msg)
        end

        def rate_limit_key(severity, progname)
          # We want to rate limit key to be as granular as possible to ensure
          #   we get one log line per unique message every X seconds
          # For example:
          #
          #     Datadog::Tracer.log.warn('first message')
          #     Datadog::Tracer.log.warn('second message')
          #
          # We want to be sure we always log both log lines every 60 seconds
          #   and not just the first message every 60 seconds

          where = ''
          if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.0.0')
            # Skip the first 5, and only select the next location
            #   - `Datadog::Logging::RateLimitedLogger::Formatter#call`
            #   - `::Logger#format_message`
            #   - `::Logger#add`
            #   - `Datadog::Logging::Logger#add`
            #   - `::Logger#log` (debug, warn, info, error, etc)
            c = caller_locations(5, 1)
            where = "#{c.first.path}-#{c.first.lineno}-#{c.first.label}-" unless c.empty?
          end

          "#{where}#{progname}-#{severity}"
        end
      end

      def initialize(*args, &block)
        super

        self.formatter ||= ::Logger::Formatter.new
        self.formatter.extend(Formatter)
      end

      def formatter=(formatter)
        formatter.extend(Formatter)
        super(formatter)
      end
    end
  end
end
