require 'ddtrace/contrib/rack/request_queue'

class QueueTimeParserTest < Minitest::Test
  include Rack::Test::Methods

  def test_nginx_header
    # ensure nginx headers are properly parsed
    headers = {}
    headers['HTTP_X_REQUEST_START'] = 't=1512379167.574'
    request_start = Datadog::Contrib::Rack::QueueTime.get_request_start(headers)
    assert_equal(1512379167.574, request_start.to_f)
  end
end
