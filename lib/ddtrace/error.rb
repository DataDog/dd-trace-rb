# Datadog global namespace
module Datadog
  # Error is a value-object responsible for sanitizing/encapsulating error data
  class Error
    ContainsMessage = ->(v) { v.respond_to?(:message) }
    attr_reader :type, :message, :backtrace

    def self.build_from(value)
      case value
      when Error then value
      when Array then new(*value)
      when Exception then new(value.class, value.message, value.backtrace)
      when ContainsMessage then new(value.class, value.message)
      else blank_error
      end
    end

    def initialize(type = nil, message = nil, backtrace = nil)
      backtrace = sanitize_backtrace(backtrace)
      @type = Utils.utf8_encode(type)
      @message = Utils.utf8_encode(message)
      @backtrace = Utils.utf8_encode(backtrace)
    end

    def self.blank_error
      @blank_error ||= Error.new
    end

    private

    def sanitize_backtrace(backtrace)
      backtrace = Array(backtrace).join("\n")
      return backtrace unless error_backtrace_strip

      backtrace.gsub!(error_backtrace_strip, "")
      backtrace
    end

    def error_backtrace_strip
      datadog_configuration.error_backtrace_strip
    end

    def datadog_configuration
      Datadog.configuration.tracer
    end
  end
end
