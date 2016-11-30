require 'helper'

require 'ddtrace/transport'
require 'ddtrace/encoding'

class UtilsTest < Minitest::Test
  def setup
    # set the transport and temporary disable the logger to prevent
    # spam in the tests output
    @default_transport = Datadog::HTTPTransport.new('localhost', '7777')
    @transport_json = Datadog::HTTPTransport.new('localhost', '7777', encoder: Datadog::Encoding::JSONEncoder.new())
    @transport_msgpack = Datadog::HTTPTransport.new('localhost', '7777', encoder: Datadog::Encoding::MsgpackEncoder.new())
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
    @default_transport.handle_response(response)
    assert true
  end

  def test_handle_response_nil
    # a nil answer should not crash the thread
    @default_transport.handle_response(nil)
    assert true
  end

  def test_send_traces
    skip unless ENV['TEST_DATADOG_INTEGRATION'] # requires a runnning agent
    traces = get_test_traces(2)

    # JSON encoding
    code = @transport_json.send(:traces, traces)
    assert_equal true, @transport_json.success?(code), "transport.send failed, code: #{code}"

    # Msgpack encoding
    code = @transport_msgpack.send(:traces, traces)
    assert_equal true, @transport_msgpack.success?(code), "transport.send failed, code: #{code}"
  end

  def test_send_services
    skip unless ENV['TEST_DATADOG_INTEGRATION'] # requires a runnning agent
    services = get_test_services()

    # JSON encoding
    code = @transport_json.send(:services, services)
    assert_equal true, @transport_json.success?(code), "transport.send failed, code: #{code}"

    # Msgpack encoding
    code = @transport_msgpack.send(:services, services)
    assert_equal true, @transport_msgpack.success?(code), "transport.send failed, code: #{code}"
  end

  def test_send_server_error
    skip unless ENV['TEST_DATADOG_INTEGRATION'] # requires a runnning agent
    bad_transport = Datadog::HTTPTransport.new('localhost', '8888')
    traces = get_test_traces(2)
    code = bad_transport.send(:traces, traces)
    assert_equal true, bad_transport.server_error?(code),
                 "transport.send did not fail (it should have failed) code: #{code}"
  end

  def test_send_router
    skip unless ENV['TEST_DATADOG_INTEGRATION'] # requires a running agent
    traces = get_test_traces(2)

    code = @default_transport.send(:admin, traces)
    assert_equal nil, code,
                 "transport.send did not return 'nil'; code: #{code}"
  end
end
