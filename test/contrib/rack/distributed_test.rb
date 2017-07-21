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
    @rack_port = RACK_PORT
  end

  def check_distributed(tracer, client, distributed, message)
    response = client.get('/distributed/')
    refute_nil(response, 'no response')
    assert_kind_of(Net::HTTPResponse, response, 'bad response type')
    assert_equal('200', response.code, 'bad response status')

    spans = tracer.writer.spans()

    assert_equal(2, spans.length, 'there should be exactly 2 spans')
    http_span, rack_span = spans
    assert_equal('http.request', http_span.name)
    assert_equal('rack.request', rack_span.name)
    if distributed
      assert_equal(rack_span.trace_id, http_span.trace_id,
                   "#{message}: http and rack spans should share the same trace id")
      assert_equal(rack_span.parent_id, http_span.span_id,
                   "#{message}: http span should be the parent of rack span")
    else
      refute_equal(rack_span.trace_id, http_span.trace_id,
                   "#{message}: http and rack spans should *not* share the same trace id")
      refute_equal(rack_span.parent_id, http_span.span_id,
                   "#{message}: http span should *not* be the parent of rack span")
    end
  end

  # rubocop:disable Metrics/MethodLength
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
      Rack::Handler::WEBrick.run(app, Port: @rack_port, Logger: log, AccessLog: access_log) {}
    end

    # this will create extra rack spans but we really need for the server to be up
    wait_http_server 'http://' + RACK_HOST + ':' + @rack_port.to_s, 5
    tracer.writer.spans() # flush extra rack spans

    assert_equal(false, Datadog::Contrib::HTTP.distributed_tracing_enabled,
                 'by default, distributed tracing is disabled')
    client = Net::HTTP.new(RACK_HOST, @rack_port)
    pin = Datadog::Pin.get_from(client)
    pin.config = { distributed_tracing_enabled: true }
    pin.tracer = tracer
    check_distributed(tracer, client, true, 'globally disabled, enabled for this client')

    Datadog::Contrib::HTTP.distributed_tracing_enabled = true
    assert_equal(true, Datadog::Contrib::HTTP.distributed_tracing_enabled,
                 'distributed tracing is now enabled')
    client = Net::HTTP.new(RACK_HOST, @rack_port)
    pin = Datadog::Pin.get_from(client)
    pin.config = nil
    pin.tracer = tracer
    check_distributed(tracer, client, true, 'globally enabled, default client')

    assert_equal(true, Datadog::Contrib::HTTP.distributed_tracing_enabled,
                 'distributed tracing is still globally enabled')
    client = Net::HTTP.new(RACK_HOST, @rack_port)
    pin = Datadog::Pin.get_from(client)
    pin.config = { distributed_tracing_enabled: false }
    pin.tracer = tracer
    check_distributed(tracer, client, false, 'globally enabled, disabled for this client')

    Datadog::Contrib::HTTP.distributed_tracing_enabled = false
    assert_equal(false, Datadog::Contrib::HTTP.distributed_tracing_enabled,
                 'by default, distributed tracing is disabled')
    client = Net::HTTP.new(RACK_HOST, @rack_port)
    pin = Datadog::Pin.get_from(client)
    pin.tracer = tracer
    check_distributed(tracer, client, false, 'globally disabled, default client')
  end
end
