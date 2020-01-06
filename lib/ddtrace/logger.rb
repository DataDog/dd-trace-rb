require 'logger'

module Datadog
  LOG_PREFIX = 'ddtrace'.freeze

  # A custom logger with minor enhancements:
  # - progname defaults to ddtrace to clearly identify Datadog dd-trace-rb related messages
  # - adds last caller stack-trace info to know where the message comes from
  class Logger < ::Logger
    # Global, memoized, lazy initialized instance of a logger that is used within the the Datadog
    # namespace. This logger outputs to +STDOUT+ by default, and is considered thread-safe.
    class << self
      def log
        unless defined? @logger
          @logger = Datadog::Logger.new(STDOUT)
          @logger.level = Logger::WARN
        end
        @logger
      end

      # Override the default logger with a custom one.
      def log=(logger)
        return unless logger
        return unless logger.respond_to? :methods
        return unless logger.respond_to? :error
        if logger.respond_to? :methods
          unimplemented = new(STDOUT).methods - logger.methods
          unless unimplemented.empty?
            logger.error("logger #{logger} does not implement #{unimplemented}")
            return
          end
        end
        @logger = logger
      end

      # Activate the debug mode providing more information related to tracer usage
      # Default to Warn level unless using custom logger
      def debug_logging=(value)
        if value
          log.level = Logger::DEBUG
        elsif log.is_a?(Datadog::Logger)
          log.level = Logger::WARN
        end
      end

      # Return if the debug mode is activated or not
      def debug_logging
        log.level == Logger::DEBUG
      end
    end

    def initialize(*args, &block)
      super
      self.progname = LOG_PREFIX
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
