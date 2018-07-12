require('ddtrace/contrib/rack/request_queue')
class QueueTimeParserTest < Minitest::Test
  include(Rack::Test::Methods)
  it('nginx header') do
    headers = {}
    headers['HTTP_X_REQUEST_START'] = 't=1512379167.574'
    request_start = Datadog::Contrib::Rack::QueueTime.get_request_start(headers)
    expect(request_start.to_f).to(eq(1512379167.574))
  end
end
