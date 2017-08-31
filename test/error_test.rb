require 'helper'
require 'ddtrace/error'

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

    def test_nil_coercion
      error = Error.build_from(nil)

      assert_empty(error.type)
      assert_empty(error.message)
      assert_empty(error.backtrace)
    end
  end
end
