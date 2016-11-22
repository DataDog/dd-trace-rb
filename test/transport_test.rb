require 'helper'

require 'ddtrace/transport'
require 'ddtrace/encoding'

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

  def test_send_traces
    skip unless ENV['TEST_DATADOG_INTEGRATION'] # requires a runnning agent
    traces = get_test_traces(2)
    encoded_spans = Datadog::Encoding.encode_spans(traces)
    code = @transport.send('/v0.2/traces', encoded_spans)
    assert_equal true, @transport.success?(code), "transport.send failed, code: #{code}"
  end

  def test_send_services
    skip unless ENV['TEST_DATADOG_INTEGRATION'] # requires a runnning agent
    services = get_test_services
    encoded_services = Datadog::Encoding.encode_services(services)
    code = @transport.send('/v0.2/services', encoded_services)
    assert_equal true, @transport.success?(code), "transport.send failed, code: #{code}"
  end

  def test_send_server_error
    skip unless ENV['TEST_DATADOG_INTEGRATION'] # requires a runnning agent
    bad_transport = Datadog::HTTPTransport.new('localhost', '8888')
    traces = get_test_traces(2)
    spans = Datadog::Encoding.encode_spans(traces)
    code = bad_transport.send('/v0.2/traces', spans)
    assert_equal true, bad_transport.server_error?(code),
                 "transport.send did not fail (it should have failed) code: #{code}"
  end

  def test_send_404
    skip unless ENV['TEST_DATADOG_INTEGRATION'] # requires a running agent
    traces = get_test_traces(2)
    spans = Datadog::Encoding.encode_spans(traces)
    code = @transport.send('/admin.php', spans)
    assert_equal 404, code,
                 "transport.send did not return 404 (it should have returned 404) code: #{code}"
  end
end
