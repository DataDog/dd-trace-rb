# Datadog global namespace
module Datadog
  # Error is a value-object responsible for sanitizing/encapsulating error data
  class Error
    attr_reader :type, :message, :backtrace

    def self.build_from(value)
      case value
      when Error then value
      when Array then new(*value)
      when Exception then new(value.class, value.message, value.backtrace)
      when ContainsMessage then new(value.class, value.message)
      else BlankError
      end
    end

    def initialize(type = nil, message = nil, backtrace = nil)
      backtrace = Array(backtrace).join("\n")
      @type = Utils.utf8_encode(type)
      @message = Utils.utf8_encode(message)
      @backtrace = Utils.utf8_encode(backtrace)
    end

    BlankError = Error.new
    ContainsMessage = ->(v) { v.respond_to?(:message) }
  end
end
