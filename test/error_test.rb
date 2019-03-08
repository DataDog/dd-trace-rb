require 'helper'
require 'ddtrace/error'
require 'net/http'

module Datadog
  class ErrorTest < Minitest::Test
    CustomMessage = Struct.new(:message)

    def setup
      @error = Error.new('StandardError', 'message', %w[x y z])
    end

    def test_type
      assert_equal('StandardError', @error.type)
    end

    def test_message
      assert_equal('message', @error.message)
    end

    def test_backtrace
      assert_equal("x\ny\nz", @error.backtrace)
    end

    def test_default_values
      error = Error.new

      assert_empty(error.type)
      assert_empty(error.message)
      assert_empty(error.backtrace)
    end

    # Empty strings were being interpreted as ASCII strings breaking `msgpack`
    # decoding on the agent-side.
    def test_enconding
      error = Datadog::Error.new

      assert_equal(::Encoding::UTF_8, error.type.encoding)
      assert_equal(::Encoding::UTF_8, error.message.encoding)
      assert_equal(::Encoding::UTF_8, error.backtrace.encoding)
    end

    def test_array_coercion
      error_payload = ['ZeroDivisionError', 'divided by 0']
      error = Error.build_from(error_payload)

      assert_equal('ZeroDivisionError', error.type)
      assert_equal('divided by 0', error.message)
      assert_empty(error.backtrace)
    end

    def test_exception_coercion
      exception = ZeroDivisionError.new('divided by 0')
      error = Error.build_from(exception)

      assert_equal('ZeroDivisionError', error.type)
      assert_equal('divided by 0', error.message)
      assert_empty(error.backtrace)
    end

    def test_message_coercion
      message = CustomMessage.new('custom-message')
      error = Error.build_from(message)

      assert_equal('Datadog::ErrorTest::CustomMessage', error.type)
      assert_equal('custom-message', error.message)
      assert_empty(error.backtrace)
    end

    def test_net_http_response_coercion
      # https://github.com/ruby/ruby/blob/4444025d16ae1a586eee6a0ac9bdd09e33833f3c/test/net/http/test_httpresponse.rb#L37-L55
      io = Net::BufferedIO.new(StringIO.new(<<EOS))
HTTP/1.1 404 Not Found
Content-Length: 13
Connection: close

response body
EOS

      response = Net::HTTPResponse.read_new(io)
      response.reading_body(io, true) {}

      error = Error.build_from(response)

      assert_equal('Net::HTTPNotFound', error.type)
      assert_equal('response body', error.message)
      assert_empty(error.backtrace)
    end

    def test_net_http_response_no_body_coercion
      # https://github.com/ruby/ruby/blob/4444025d16ae1a586eee6a0ac9bdd09e33833f3c/test/net/http/test_httpresponse.rb#L37-L55
      io = Net::BufferedIO.new(StringIO.new(<<EOS))
HTTP/1.1 204 No Content
Content-Length: 0
Connection: close

EOS

      response = Net::HTTPResponse.read_new(io)
      response.reading_body(io, true) {}

      error = Error.build_from(response)

      assert_equal('Net::HTTPNoContent', error.type)
      assert_equal('No Content', error.message)
      assert_empty(error.backtrace)
    end

    def test_nil_coercion
      error = Error.build_from(nil)

      assert_empty(error.type)
      assert_empty(error.message)
      assert_empty(error.backtrace)
    end

    def test_regression_non_utf8_compatible
      exception = StandardError.new("\xC2".force_encoding(::Encoding::ASCII_8BIT))
      error = Error.build_from(exception)

      assert_equal('StandardError', @error.type)
      assert_empty(error.message)
      assert_empty(error.backtrace)
    end
  end
end
