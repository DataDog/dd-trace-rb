require 'helper'

require 'ddtrace/transport'

class UtilsTest < Minitest::Test
  def setup
    # set the transport and temporary disable the logger to prevent
    # spam in the tests output
    @transport = Datadog::HTTPTransport.new('localhost', '7777')
    @original_level = Datadog::Tracer.log.level
    Datadog::Tracer.log.level = Logger::FATAL
  end

  def teardown
    # set the original log level
    Datadog::Tracer.log.level = @original_level
  end

  def test_handle_response
    # a response must be handled as expected
    response = Net::HTTPResponse.new(1.0, 200, 'OK')
    @transport.handle_response(response)
    assert true
  end

  def test_handle_response_nil
    # a nil answer should not crash the thread
    @transport.handle_response(nil)
    assert true
  end
end
