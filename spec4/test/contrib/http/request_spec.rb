require('time')
require('contrib/elasticsearch/test_helper')
require('ddtrace')
require('helper')
require('json')
class HTTPRequestTest < Minitest::Test
  ELASTICSEARCH_HOST = ENV.fetch('TEST_ELASTICSEARCH_HOST', '127.0.0.1').freeze
  ELASTICSEARCH_PORT = ENV.fetch('TEST_ELASTICSEARCH_PORT', 9200).freeze
  ELASTICSEARCH_SERVER = "http://#{ELASTICSEARCH_HOST}:#{ELASTICSEARCH_PORT}".freeze
  before do
    Datadog.configure do |c|
      c.tracer(hostname: ENV.fetch('TEST_DDAGENT_HOST', 'localhost'))
      c.use(:http)
    end
    @tracer = get_test_tracer
    wait_http_server(ELASTICSEARCH_SERVER, 60)
    @client = Net::HTTP.new(ELASTICSEARCH_HOST, ELASTICSEARCH_PORT)
    pin = Datadog::Pin.get_from(@client)
    pin.tracer = @tracer
  end
  it('get request') do
    response = @client.get('_cluster/health')
    expect(response.code).to(eq('200'))
    content = JSON.parse(response.body)
    assert_kind_of(Hash, content, 'bad content')
    spans = @tracer.writer.spans
    expect(spans.length).to(eq(1))
    span = spans[0]
    expect(span.name).to(eq('http.request'))
    expect(span.service).to(eq('net/http'))
    expect(span.resource).to(eq('GET'))
    expect(span.get_tag('http.url')).to(eq('_cluster/health'))
    expect(span.get_tag('http.method')).to(eq('GET'))
    expect(span.get_tag('http.status_code')).to(eq('200'))
    expect(span.status).to(eq(0))
  end
  it('post request') do
    response = @client.post('/my/thing/42', '{ "foo": "bar" }')
    assert_operator(200, :<=, response.code.to_i, 'bad response status')
    assert_operator(201, :>=, response.code.to_i, 'bad response status')
    spans = @tracer.writer.spans
    expect(spans.length).to(eq(1))
    span = spans[0]
    expect(span.name).to(eq('http.request'))
    expect(span.service).to(eq('net/http'))
    expect(span.resource).to(eq('POST'))
    expect(span.get_tag('http.url')).to(eq('/my/thing/42'))
    expect(span.get_tag('http.method')).to(eq('POST'))
    expect(span.get_tag('out.host')).to(eq(ELASTICSEARCH_HOST))
    expect(span.get_tag('out.port')).to(eq(ELASTICSEARCH_PORT.to_s))
    expect(span.status).to(eq(0))
  end
  it('404') do
    response = @client.get('/admin.php?user=admin&passwd=123456')
    expect(response.code).to(eq('404'))
    spans = @tracer.writer.spans
    expect(spans.length).to(eq(1))
    span = spans[0]
    expect(span.name).to(eq('http.request'))
    expect(span.service).to(eq('net/http'))
    expect(span.resource).to(eq('GET'))
    expect(span.get_tag('http.url')).to(eq('/admin.php?user=admin&passwd=123456'))
    expect(span.get_tag('http.method')).to(eq('GET'))
    expect(span.get_tag('http.status_code')).to(eq('404'))
    expect(span.get_tag('out.host')).to(eq(ELASTICSEARCH_HOST))
    expect(span.get_tag('out.port')).to(eq(ELASTICSEARCH_PORT.to_s))
    expect(span.status).to(eq(1))
    expect(span.get_tag('error.type')).to(eq('Net::HTTPNotFound'))
  end
  it('pin block call') do
    Net::HTTP.start(ELASTICSEARCH_HOST, ELASTICSEARCH_PORT) do |http|
      pin = Datadog::Pin.get_from(http)
      refute_nil(pin)
      pin.tracer = @tracer
      request = Net::HTTP::Get.new('/_cluster/health')
      response = http.request(request)
      assert_kind_of(Net::HTTPResponse, response)
      spans = @tracer.writer.spans
      expect(spans.length).to(eq(1))
      span = spans[0]
      expect(span.name).to(eq('http.request'))
      expect(span.service).to(eq('net/http'))
      expect(span.resource).to(eq('GET'))
      expect(span.get_tag('http.url')).to(eq('/_cluster/health'))
      expect(span.get_tag('http.method')).to(eq('GET'))
      expect(span.get_tag('http.status_code')).to(eq('200'))
      expect(span.get_tag('out.host')).to(eq(ELASTICSEARCH_HOST))
      expect(span.get_tag('out.port')).to(eq(ELASTICSEARCH_PORT.to_s))
    end
  end
  it('pin override') do
    pin = Datadog::Pin.get_from(@client)
    pin.service = 'bar'
    response = @client.get('_cluster/health')
    expect(response.code).to(eq('200'))
    spans = @tracer.writer.spans
    expect(spans.length).to(eq(1))
    span = spans[0]
    expect(span.name).to(eq('http.request'))
    expect(span.service).to(eq('bar'))
  end
  it('distributed tracing headers') do
    Datadog.configuration[:http][:distributed_tracing] = true
    pin = Datadog::Pin.get_from(@client)
    spy = StringIO.new
    pin.tracer.trace('foo.bar') do |span|
      span.context.sampling_priority = 10
      @client.set_debug_output(spy)
      @client.get('/_cluster/health')
    end
    request_data = spy.string
    expect(request_data).to(match(/x-datadog-parent-id/i))
    expect(request_data).to(match(/x-datadog-trace-id/i))
    expect(request_data).to(match(/x-datadog-sampling-priority: 10/i))
    Datadog.configuration[:http][:distributed_tracing] = false
  end
  it('disabled distributed tracing') do
    Datadog.configuration[:http][:distributed_tracing] = false
    spy = StringIO.new
    @client.set_debug_output(spy)
    @client.get('/_cluster/health')
    request_data = spy.string
    refute_match(/x-datadog-parent-id/i, request_data)
    refute_match(/x-datadog-trace-id/i, request_data)
    refute_match(/x-datadog-sampling-priority/i, request_data)
  end
  it('distributed tracing when tracer is disabled') do
    Datadog.configuration[:http][:distributed_tracing] = true
    pin = Datadog::Pin.get_from(@client)
    pin.tracer.configure(enabled: false)
    spy = StringIO.new
    @client.set_debug_output(spy)
    @client.get('/_cluster/health')
    request_data = spy.string
    refute_match(/x-datadog-parent-id/i, request_data)
    refute_match(/x-datadog-trace-id/i, request_data)
    refute_match(/x-datadog-sampling-priority/i, request_data)
  end
end
