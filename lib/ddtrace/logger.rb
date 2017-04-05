require 'logger'

module Datadog
  LOG_PREFIX = 'ddtrace'.freeze

  # A custom logger with minor enhancements:
  # - progname defaults to ddtrace to clearly identify Datadog dd-trace-rb related messages
  # - adds last caller stack-trace info to know where the message comes from
  class Logger < ::Logger
    def initialize(*args, &block)
      super
      self.progname = LOG_PREFIX
    end

    def add(severity, message = nil, progname = nil, &block)
      return super unless debug?

      # We are in debug mode, add stack trace to help debugging
      where = ''
      c = caller
      where = "(#{c[1]}) " if c.length > 1

      if block_given?
        super(severity, message, progname) do
          "#{where}#{yield}"
        end
      else
        super(severity, message, "#{where}#{progname}")
      end
    end

    alias log add
  end
end
