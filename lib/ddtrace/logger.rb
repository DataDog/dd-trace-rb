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

      @buckets = {}
    end

    def add(severity, message = nil, progname = nil, &block)
      c = nil
      skipped_messages = ''

      # Logging rate of 0 means log everything, so skip bucket checking
      if Datadog.configuration.logging_rate > 0
        c = caller
        key = rate_limit_key(severity, progname, c)
        last_bucket = @buckets[key]
        current_bucket = Time.now.to_i / Datadog.configuration.logging_rate

        if last_bucket.nil? || last_bucket[:bucket] != current_bucket
          # Get the previous number of skipped messages to append to message
          unless last_bucket.nil? || last_bucket[:skipped].zero?
            skipped_messages = ", #{last_bucket[:skipped]} additional messages skipped"
          end

          # We are in a new time bucket, and are not rate limited
          # Reset the bucket for this key
          @buckets[key] = { bucket: current_bucket,
                            skipped: 0 }
        else
          @buckets[key][:skipped] += 1

          # We were in an existing bucket we already logged for, do not log any more
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
      where = c.length > 1 ? c[1] : ''
      "#{where}-#{self.progname}-#{progname}-#{severity}"
    end
  end
end
