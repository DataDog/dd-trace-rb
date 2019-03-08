require 'net/http'

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
      when Net::HTTPResponse then build_from_http_response(value)
      when ContainsMessage then new(value.class, value.message)
      else BlankError
      end
    end

    def self.build_from_http_response(response)
      message = response.message
      if response.class.body_permitted? && !response.body.nil?
        message = response.body[0...4095]
      end

      new(response.class, message)
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
