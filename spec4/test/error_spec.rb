require('spec_helper')
require('ddtrace/error')
RSpec.describe Datadog::Error do
    CustomMessage = Struct.new(:message)
    before { @error = described_class.new('StandardError', 'message', %w[x y z]) }
    it('type') { expect(@error.type).to(eq('StandardError')) }
    it('message') { expect(@error.message).to(eq('message')) }
    it('backtrace') { expect(@error.backtrace).to(eq("x\ny\nz")) }
    it('default values') do
      error = described_class.new
      assert_empty(error.type)
      assert_empty(error.message)
      assert_empty(error.backtrace)
    end
    it('enconding') do
      error = described_class.new
      expect(error.type.encoding).to(eq(::Encoding::UTF_8))
      expect(error.message.encoding).to(eq(::Encoding::UTF_8))
      expect(error.backtrace.encoding).to(eq(::Encoding::UTF_8))
    end
    it('array coercion') do
      error_payload = ['ZeroDivisionError', 'divided by 0']
      error = described_class.build_from(error_payload)
      expect(error.type).to(eq('ZeroDivisionError'))
      expect(error.message).to(eq('divided by 0'))
      assert_empty(error.backtrace)
    end
    it('exception coercion') do
      exception = ZeroDivisionError.new('divided by 0')
      error = described_class.build_from(exception)
      expect(error.type).to(eq('ZeroDivisionError'))
      expect(error.message).to(eq('divided by 0'))
      assert_empty(error.backtrace)
    end
    it('message coercion') do
      message = CustomMessage.new('custom-message')
      error = described_class.build_from(message)
      expect(error.type).to(eq('described_classTest::CustomMessage'))
      expect(error.message).to(eq('custom-message'))
      assert_empty(error.backtrace)
    end
    it('nil coercion') do
      error = described_class.build_from(nil)
      assert_empty(error.type)
      assert_empty(error.message)
      assert_empty(error.backtrace)
    end
    it('regression non utf8 compatible') do
      exception = StandardError.new("\xC2".force_encoding(::Encoding::ASCII_8BIT))
      error = described_class.build_from(exception)
      expect(@error.type).to(eq('StandardError'))
      assert_empty(error.message)
      assert_empty(error.backtrace)
    end
  end
