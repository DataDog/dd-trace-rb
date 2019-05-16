require 'logger'
require 'time'

module Datadog
  LOG_PREFIX = 'ddtrace'.freeze

  # A custom logger with minor enhancements:
  # - progname defaults to ddtrace to clearly identify Datadog dd-trace-rb related messages
  # - adds last caller stack-trace info to know where the message comes from
  class Logger < ::Logger
    def initialize(*args, &block)
      super
      self.progname = LOG_PREFIX

      # Rate limit buckets
      @buckets = {}
    end

    def add(severity, message = nil, progname = nil, &block)
      where = ''
      c = nil
      skipped_messages = ''

      # Logging rate of 0 means log everything, so skip bucket checking
      if Datadog.configuration.logging_rate > 0
        # Get the call stack to determine who is logging
        c = caller

        # Get the rate limit bucket key
        key = rate_limit_key(severity, progname, c)

        # Get the currently existing bucket, if one exists
        last_bucket = @buckets[key]

        # Get the current time bucket
        # DEV: This is used to determine which logging_rate period this log occurred in
        #   e.g. (1557944138 / 60) = 25965735
        current_time_bucket = Time.now.to_i / Datadog.configuration.logging_rate

        # If no previous bucket exists or the time bucket has changed, then we can log
        if last_bucket.nil? || last_bucket[:time_bucket] != current_time_bucket
          # Get the previous number of skipped messages to append to message
          unless last_bucket.nil? || last_bucket[:skipped].zero?
            skipped_messages = ", #{last_bucket[:skipped]} additional messages skipped"
          end

          # We are in a new time bucket, and are not rate limited
          # Reset the bucket for this key
          @buckets[key] = { time_bucket: current_time_bucket,
                            skipped: 0 }

        # Otherwise, we are in an existing bucket we already logged for
        else
          # Increment the skipped count and return without logging anything
          @buckets[key][:skipped] += 1
          return
        end
      end

      # We are in debug mode, or this is an error, add stack trace to help debugging
      if debug? || severity >= ::Logger::ERROR
        c = caller if c.nil?
        where = "(#{c[1]}) " if c.length > 1
      end

      if message.nil?
        if block_given?
          super(severity, "#{message}#{skipped_messages}", progname) do
            "[#{self.progname}] #{where}#{yield}"
          end
        else
          super(severity, "#{message}#{skipped_messages}", "[#{self.progname}] #{where}#{progname}")
        end
      else
        super(severity, "[#{self.progname}] #{where}#{message}#{skipped_messages}")
      end
    end

    alias log add

    private

    def rate_limit_key(severity, progname, c)
      # We want to rate limit key to be as granular as possible to ensure
      #   we get one log line per unique message every X seconds
      # For example:
      #
      #     Datadog::Tracer.log.warn('first message')
      #     Datadog::Tracer.log.warn('second message')
      #
      # We want to be sure we always log both log lines every 60 seconds
      #   and not just the first message every 60 seconds
      # DEV: `c` is `caller` from `#add`, we pass it in so we only need to
      #   call `caller` once at most per `#add` call
      where = c.length > 1 ? c[1] : ''
      "#{where}-#{self.progname}-#{progname}-#{severity}"
    end
  end
end
