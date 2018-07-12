require('helper')
require('ddtrace/error')
module Datadog
  class ErrorTest < Minitest::Test
    CustomMessage = Struct.new(:message)
    before { @error = Error.new('StandardError', 'message', %w[x y z]) }
    it('type') { expect(@error.type).to(eq('StandardError')) }
    it('message') { expect(@error.message).to(eq('message')) }
    it('backtrace') { expect(@error.backtrace).to(eq("x\ny\nz")) }
    it('default values') do
      error = Error.new
      assert_empty(error.type)
      assert_empty(error.message)
      assert_empty(error.backtrace)
    end
    it('enconding') do
      error = Datadog::Error.new
      expect(error.type.encoding).to(eq(::Encoding::UTF_8))
      expect(error.message.encoding).to(eq(::Encoding::UTF_8))
      expect(error.backtrace.encoding).to(eq(::Encoding::UTF_8))
    end
    it('array coercion') do
      error_payload = ['ZeroDivisionError', 'divided by 0']
      error = Error.build_from(error_payload)
      expect(error.type).to(eq('ZeroDivisionError'))
      expect(error.message).to(eq('divided by 0'))
      assert_empty(error.backtrace)
    end
    it('exception coercion') do
      exception = ZeroDivisionError.new('divided by 0')
      error = Error.build_from(exception)
      expect(error.type).to(eq('ZeroDivisionError'))
      expect(error.message).to(eq('divided by 0'))
      assert_empty(error.backtrace)
    end
    it('message coercion') do
      message = CustomMessage.new('custom-message')
      error = Error.build_from(message)
      expect(error.type).to(eq('Datadog::ErrorTest::CustomMessage'))
      expect(error.message).to(eq('custom-message'))
      assert_empty(error.backtrace)
    end
    it('nil coercion') do
      error = Error.build_from(nil)
      assert_empty(error.type)
      assert_empty(error.message)
      assert_empty(error.backtrace)
    end
    it('regression non utf8 compatible') do
      exception = StandardError.new("\xC2".force_encoding(::Encoding::ASCII_8BIT))
      error = Error.build_from(exception)
      expect(@error.type).to(eq('StandardError'))
      assert_empty(error.message)
      assert_empty(error.backtrace)
    end
  end
end
