require('time')
require('contrib/elasticsearch/test_helper')
require('contrib/elasticsearch/dummy_faraday_middleware')
require('ddtrace')
require('helper')
class ESTransportTest < Minitest::Test
  ELASTICSEARCH_HOST = ENV.fetch('TEST_ELASTICSEARCH_HOST', '127.0.0.1').freeze
  ELASTICSEARCH_PORT = ENV.fetch('TEST_ELASTICSEARCH_PORT', '9200').freeze
  ELASTICSEARCH_SERVER = "http://#{ELASTICSEARCH_HOST}:#{ELASTICSEARCH_PORT}".freeze
  before do
    Datadog.configure { |c| c.use(:elasticsearch) }
    @tracer = get_test_tracer
    wait_http_server(ELASTICSEARCH_SERVER, 60)
    @client = Elasticsearch::Client.new(url: ELASTICSEARCH_SERVER) do |faraday|
      faraday.use(DummyFaradayMiddleware)
    end
    pin = Datadog::Pin.get_from(@client)
    pin.tracer = @tracer
  end
  after { @client.perform_request('DELETE', '*') }
  it('faraday middleware load') do
    assert_includes(@client.transport.connections.first.connection.builder.handlers, DummyFaradayMiddleware)
  end
  it('perform request') do
    response = @client.perform_request('GET', '_cluster/health')
    expect(response.status).to(eq(200))
    spans = @tracer.writer.spans
    expect(spans.length).to(eq(1))
    span = spans[0]
    expect(span.name).to(eq('elasticsearch.query'))
    expect(span.service).to(eq('elasticsearch'))
    expect(span.resource).to(eq('GET _cluster/health'))
    expect(span.get_tag('elasticsearch.url')).to(eq('_cluster/health'))
    expect(span.get_tag('elasticsearch.method')).to(eq('GET'))
    expect(span.get_tag('http.status_code')).to(eq('200'))
    expect(span.get_tag('elasticsearch.params')).to(be_nil)
    expect(span.get_tag('elasticsearch.body')).to(be_nil)
    expect(span.get_tag('out.host')).to(eq(ELASTICSEARCH_HOST))
    expect(span.get_tag('out.port')).to(eq(ELASTICSEARCH_PORT))
  end
  it('perform request with encoded body') do
    response = @client.perform_request('PUT', '/my/thing/1', { refresh: true }, '{"data1":"D1","data2":"D2"}')
    expect(response.status).to(eq(201))
    spans = @tracer.writer.spans
    expect(spans.length).to(eq(1))
    span = spans[0]
    expect(span.name).to(eq('elasticsearch.query'))
    expect(span.service).to(eq('elasticsearch'))
    expect(span.resource).to(eq('PUT /my/thing/?'))
    expect(span.get_tag('elasticsearch.url')).to(eq('/my/thing/1'))
    expect(span.get_tag('elasticsearch.method')).to(eq('PUT'))
    expect(span.get_tag('http.status_code')).to(eq('201'))
    expect(span.get_tag('elasticsearch.params')).to(eq('{"refresh":true}'))
    expect(span.get_tag('elasticsearch.body')).to(eq('{"data1":"?","data2":"?"}'))
  end
  def roundtrip_put
    response = @client.perform_request('PUT', '/my/thing/1', { refresh: true }, data1: 'D1', data2: 'D2')
    assert_equal(201, response.status, 'bad response status')
    spans = @tracer.writer.spans
    assert_equal(1, spans.length)
    span = spans[0]
    assert_equal('elasticsearch.query', span.name)
    assert_equal('elasticsearch', span.service)
    assert_equal('PUT /my/thing/?', span.resource)
    assert_equal('/my/thing/1', span.get_tag('elasticsearch.url'))
    assert_equal('PUT', span.get_tag('elasticsearch.method'))
    assert_equal('201', span.get_tag('http.status_code'))
    assert_equal('{"refresh":true}', span.get_tag('elasticsearch.params'))
    assert_equal('{"data1":"?","data2":"?"}', span.get_tag('elasticsearch.body'))
  end

  def roundtrip_get
    response = @client.perform_request('GET', '/my/thing/1')
    assert_equal(200, response.status, 'bad response status')
    body = response.body
    assert_kind_of(Hash, body, 'bad response body')
    assert_equal('my', body['_index'])
    assert_equal('thing', body['_type'])
    assert_equal('1', body['_id'])
    assert_equal(true, body['found'])
    assert_equal({ 'data1' => 'D1', 'data2' => 'D2' }, body['_source'])
    spans = @tracer.writer.spans
    assert_equal(1, spans.length)
    span = spans[0]
    assert_equal('elasticsearch.query', span.name)
    assert_equal('elasticsearch', span.service)
    assert_equal('GET /my/thing/?', span.resource)
    assert_equal('/my/thing/1', span.get_tag('elasticsearch.url'))
    assert_equal('GET', span.get_tag('elasticsearch.method'))
    assert_nil(span.get_tag('elasticsearch.params'))
    assert_nil(span.get_tag('elasticsearch.body'))
  end
  it('roundtrip') do
    roundtrip_put
    roundtrip_get
  end
  it('pin override') do
    pin = Datadog::Pin.get_from(@client)
    pin.service = 'bar'
    response = @client.perform_request('GET', '_cluster/health')
    expect(response.status).to(eq(200))
    spans = @tracer.writer.spans
    expect(spans.length).to(eq(1))
    span = spans[0]
    expect(span.name).to(eq('elasticsearch.query'))
    expect(span.service).to(eq('bar'))
  end
end
