# frozen_string_literal: true

require "logger"

module Datadog
  module Core
    # A custom logger with minor enhancements:
    # - progname defaults to datadog to clearly identify Datadog dd-trace-rb related messages
    # - adds last caller stack-trace info to know where the message comes from
    # @public_api
    class Logger < ::Logger
      PREFIX = "datadog"
      # Not `__dir__`: it resolves symlinks, unlike the paths in `caller_locations`.
      LIB_DATADOG_DIR = File.dirname(File.dirname(__FILE__)) + "/"
      private_constant :LIB_DATADOG_DIR

      def initialize(*args, &block)
        super
        self.progname = PREFIX
        self.level = ::Logger::INFO
      end

      def add(severity, message = nil, progname = nil, &block)
        where = ""

        # We are in debug mode, or this is an error, add stack trace to help debugging
        if debug? || severity >= ::Logger::ERROR
          location = caller_locations(2, 1)&.first
          where = "(#{location.to_s.delete_prefix(LIB_DATADOG_DIR)}) " if location
        end

        if message.nil?
          if block
            super(severity, nil, progname) do
              "[#{self.progname}] #{where}#{yield}"
            end
          else
            super(severity, message, "[#{self.progname}] #{where}#{progname}")
          end
        else
          super(severity, "[#{self.progname}] #{where}#{message}")
        end
      end

      alias_method :log, :add
    end
  end
end
