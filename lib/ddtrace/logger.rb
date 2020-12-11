require 'logger'

module Datadog
  # A custom logger with minor enhancements:
  # - progname defaults to ddtrace to clearly identify Datadog dd-trace-rb related messages
  # - adds last caller stack-trace info to know where the message comes from
  class Logger < ::Logger
    PREFIX = 'ddtrace'.freeze

    def initialize(*args, &block)
      super
      self.progname = PREFIX
      self.level = ::Logger::INFO
    end

    def add(severity, message = nil, progname = nil, &block)
      where = ''

      # We are in debug mode, or this is an error, add stack trace to help debugging
      if debug? || severity >= ::Logger::ERROR
        c = caller
        where = "(#{c[1]}) " if c.length > 1
      end

      if message.nil?
        if block_given?
          super(severity, message, progname) do
            "[#{self.progname}] #{where}#{yield}"
          end
        else
          super(severity, message, "[#{self.progname}] #{where}#{progname}")
        end
      else
        super(severity, "[#{self.progname}] #{where}#{message}")
      end
    end

    alias log add
  end
end
