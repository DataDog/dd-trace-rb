require 'stringio'
require 'webrick'
require 'contrib/rack/helpers'
require 'contrib/http/test_helper'

class EchoApp
  def call(env)
    http_verb = env['REQUEST_METHOD']
    status = 200
    headers = {}
    body = ["got #{http_verb} request\n"]

    [status, headers, body]
  end
end

class DistributedTest < Minitest::Test
  RACK_HOST = 'localhost'.freeze
  RACK_PORT = 9292

  def setup
    @tracer = get_test_tracer
  end

  def test_net_http_get
    tracer = @tracer

    app = Rack::Builder.new do
      use Datadog::Contrib::Rack::TraceMiddleware, tracer: tracer, distributed_tracing_enabled: true
      run EchoApp.new
    end

    @log_buf = StringIO.new
    log = WEBrick::Log.new @log_buf
    access_log = [
      [@log_buf, WEBrick::AccessLog::COMBINED_LOG_FORMAT]
    ]

    Thread.new do
      Rack::Handler::WEBrick.run(app, Port: RACK_PORT, Logger: log, AccessLog: access_log) {}
    end

    # this will create extra rack spans but we really need for the server to be up
    wait_http_server 'http://' + RACK_HOST + ':' + RACK_PORT.to_s, 5

    client = Net::HTTP.new(RACK_HOST, RACK_PORT)
    pin = Datadog::Pin.get_from(client)
    pin.config = { distributed_tracing_enabled: true }
    pin.tracer = @tracer

    response = client.get('/distributed/')
    refute_nil(response, 'no response')
    assert_kind_of(Net::HTTPResponse, response, 'bad response type')
    assert_equal('200', response.code, 'bad response status')

    spans = @tracer.writer.spans()

    rack_span = nil
    http_span = nil
    spans.each do |span|
      # iterate on all spans so that we can find
      # - a rack span with a parent
      # - an http request span
      # We do this because there are several "uninteresting" rack responses
      # which correspond to polling the server before it's up. We just want to
      # ignore those
      rack_span = span if !span.parent_id.zero? && span.name == 'rack.request'
      http_span = span if span.name == 'http.request'
    end
    refute_nil(rack_span, "unable to find a rack span with a parent in: #{spans}")
    refute_nil(http_span, "unable to find an http span in: #{spans}")

    assert_equal(rack_span.trace_id, http_span.trace_id, 'http and rack spans should share the same trace id')
    assert_equal(rack_span.parent_id, http_span.span_id, 'http span should be the parent of rack span')
  end
end
