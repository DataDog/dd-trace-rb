require('stringio')
require('webrick')
require('contrib/rack/helpers')
require('contrib/http/test_helper')
require('spec_helper')
class EchoApp
  def call(env)
    http_verb = env['REQUEST_METHOD']
    status = 200
    headers = {}
    body = ["got #{http_verb} request\n"]
    [status, headers, body]
  end
end

RSpec.describe 'Distributed' do
  RACK_HOST = 'localhost'.freeze
  RACK_PORT = 9292
  before do
    super
    @rack_port = RACK_PORT
    Datadog.configure do |c|
      c.use(:rack, tracer: @tracer, distributed_tracing: true)
    end
  end

  def check_distributed(tracer, client, distributed, message)
    response = client.get('/distributed/')
    refute_nil(response, 'no response')
    assert_kind_of(Net::HTTPResponse, response, 'bad response type')
    expect(response.code).to eq('200', "bad response status log=#{@log_buf.string}")
    spans = tracer.writer.spans
    expect(spans.length).to eq(2, 'there should be exactly 2 spans')
    http_span, rack_span = spans
    expect(http_span.name).to eq('http.request')
    expect(rack_span.name).to eq('rack.request')
    if distributed
      expect(http_span.trace_id).to eq(
        rack_span.trace_id,
        "#{message}: http and rack spans should share the same trace id"
      )
      expect(http_span.span_id).to eq(
        rack_span.parent_id,
        "#{message}: http span should be the parent of rack span"
      )
    else
      expect(http_span.trace_id).not_to eq(
        rack_span.trace_id,
        "#{message}: http and rack spans should *not* share the same trace id"
      )
      expect(http_span.span_id).not_to eq(
        rack_span.parent_id,
        "#{message}: http span should *not* be the parent of rack span"
      )
    end
  end

  it('net http get') do
    tracer = @tracer
    app = Rack::Builder.new do
      use(Datadog::Contrib::Rack::TraceMiddleware)
      run(EchoApp.new)
    end
    @log_buf = StringIO.new
    log = WEBrick::Log.new(@log_buf)
    access_log = [[@log_buf, WEBrick::AccessLog::COMBINED_LOG_FORMAT]]
    Thread.new do
      Rack::Handler::WEBrick.run(app, Port: @rack_port, Logger: log, AccessLog: access_log) do
      end
    end
    wait_http_server(((('http://' + RACK_HOST) + ':') + @rack_port.to_s), 5)
    tracer.writer.spans
    expect(Datadog.configuration[:http][:distributed_tracing]).to(eq(false))
    client = Net::HTTP.new(RACK_HOST, @rack_port)
    pin = Datadog::Pin.get_from(client)
    pin.config = { distributed_tracing: true }
    pin.tracer = tracer
    check_distributed(tracer, client, true, 'globally disabled, enabled for this client')
    Datadog.configuration[:http][:distributed_tracing] = true
    expect(Datadog.configuration[:http][:distributed_tracing]).to(eq(true))
    client = Net::HTTP.new(RACK_HOST, @rack_port)
    pin = Datadog::Pin.get_from(client)
    pin.config = nil
    pin.tracer = tracer
    check_distributed(tracer, client, true, 'globally enabled, default client')
    expect(Datadog.configuration[:http][:distributed_tracing]).to(eq(true))
    client = Net::HTTP.new(RACK_HOST, @rack_port)
    pin = Datadog::Pin.get_from(client)
    pin.config = { distributed_tracing: false }
    pin.tracer = tracer
    check_distributed(tracer, client, false, 'globally enabled, disabled for this client')
    Datadog.configuration[:http][:distributed_tracing] = false
    expect(Datadog.configuration[:http][:distributed_tracing]).to(eq(false))
    client = Net::HTTP.new(RACK_HOST, @rack_port)
    pin = Datadog::Pin.get_from(client)
    pin.tracer = tracer
    check_distributed(tracer, client, false, 'globally disabled, default client')
  end
end
