require 'time'
require 'contrib/elasticsearch/test_helper'
require 'ddtrace'
require 'helper'
require 'json'

class HTTPRequestTest < Minitest::Test
  ELASTICSEARCH_HOST = ENV.fetch('TEST_ELASTICSEARCH_HOST', '127.0.0.1').freeze
  ELASTICSEARCH_PORT = ENV.fetch('TEST_ELASTICSEARCH_PORT', 9200).freeze
  ELASTICSEARCH_SERVER = "http://#{ELASTICSEARCH_HOST}:#{ELASTICSEARCH_PORT}".freeze

  def setup
    Datadog.configure do |c|
      c.tracer hostname: ENV.fetch('TEST_DDAGENT_HOST', 'localhost')
      c.use :http
    end

    @tracer = get_test_tracer

    # wait until it's really running, docker-compose can be slow
    wait_http_server ELASTICSEARCH_SERVER, 60

    @client = Net::HTTP.new(ELASTICSEARCH_HOST, ELASTICSEARCH_PORT)
    pin = Datadog::Pin.get_from(@client)
    pin.tracer = @tracer
  end

  def test_get_request
    response = @client.get('_cluster/health')
    assert_equal('200', response.code, 'bad response status')
    content = JSON.parse(response.body)
    assert_kind_of(Hash, content, 'bad content')
    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)
    span = spans[0]
    assert_equal('http.request', span.name)
    assert_equal('net/http', span.service)
    assert_equal('GET', span.resource)
    assert_equal('_cluster/health', span.get_tag('http.url'))
    assert_equal('GET', span.get_tag('http.method'))
    assert_equal('200', span.get_tag('http.status_code'))
    assert_equal(0, span.status, 'this should not be an error')
  end

  def test_post_request
    response = @client.post('/my/thing/42', '{ "foo": "bar" }')
    assert_operator(200, :<=, response.code.to_i, 'bad response status')
    assert_operator(201, :>=, response.code.to_i, 'bad response status')
    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)
    span = spans[0]
    assert_equal('http.request', span.name)
    assert_equal('net/http', span.service)
    assert_equal('POST', span.resource)
    assert_equal('/my/thing/42', span.get_tag('http.url'))
    assert_equal('POST', span.get_tag('http.method'))
    assert_equal(ELASTICSEARCH_HOST, span.get_tag('out.host'))
    assert_equal(ELASTICSEARCH_PORT.to_s, span.get_tag('out.port'))
    assert_equal(0, span.status, 'this should not be an error')
  end

  def test_404
    response = @client.get('/admin.php?user=admin&passwd=123456')
    assert_equal('404', response.code, 'bad response status')
    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)
    span = spans[0]
    assert_equal('http.request', span.name)
    assert_equal('net/http', span.service)
    assert_equal('GET', span.resource)
    assert_equal('/admin.php?user=admin&passwd=123456', span.get_tag('http.url'))
    assert_equal('GET', span.get_tag('http.method'))
    assert_equal('404', span.get_tag('http.status_code'))
    assert_equal(ELASTICSEARCH_HOST, span.get_tag('out.host'))
    assert_equal(ELASTICSEARCH_PORT.to_s, span.get_tag('out.port'))
    assert_equal(1, span.status, 'this should be an error (404)')
    assert_equal('Net::HTTPNotFound', span.get_tag('error.type'))
  end

  def test_pin_block_call
    Net::HTTP.start(ELASTICSEARCH_HOST, ELASTICSEARCH_PORT) do |http|
      pin = Datadog::Pin.get_from(http)
      refute_nil(pin)
      pin.tracer = @tracer

      request = Net::HTTP::Get.new '/_cluster/health'
      response = http.request request
      assert_kind_of(Net::HTTPResponse, response)

      spans = @tracer.writer.spans()
      assert_equal(1, spans.length)
      span = spans[0]
      assert_equal('http.request', span.name)
      assert_equal('net/http', span.service)
      assert_equal('GET', span.resource)
      assert_equal('/_cluster/health', span.get_tag('http.url'))
      assert_equal('GET', span.get_tag('http.method'))
      assert_equal('200', span.get_tag('http.status_code'))
      assert_equal(ELASTICSEARCH_HOST, span.get_tag('out.host'))
      assert_equal(ELASTICSEARCH_PORT.to_s, span.get_tag('out.port'))
    end
  end

  def test_pin_override
    pin = Datadog::Pin.get_from(@client)
    pin.service = 'bar'
    response = @client.get('_cluster/health')
    assert_equal('200', response.code, 'bad response status')
    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)
    span = spans[0]
    assert_equal('http.request', span.name)
    assert_equal('bar', span.service)
  end

  def test_distributed_tracing_headers
    Datadog.configuration[:http][:distributed_tracing] = true

    pin = Datadog::Pin.get_from(@client)
    spy = StringIO.new

    pin.tracer.trace('foo.bar') do |span|
      span.context.sampling_priority = 10
      @client.set_debug_output(spy)
      @client.get('/_cluster/health')
    end

    request_data = spy.string
    assert_match(/x-datadog-parent-id/i, request_data)
    assert_match(/x-datadog-trace-id/i, request_data)
    assert_match(/x-datadog-sampling-priority: 10/i, request_data)

    Datadog.configuration[:http][:distributed_tracing] = false
  end

  def test_disabled_distributed_tracing
    Datadog.configuration[:http][:distributed_tracing] = false

    spy = StringIO.new
    @client.set_debug_output(spy)
    @client.get('/_cluster/health')

    request_data = spy.string
    refute_match(/x-datadog-parent-id/i, request_data)
    refute_match(/x-datadog-trace-id/i, request_data)
    refute_match(/x-datadog-sampling-priority/i, request_data)
  end

  def test_distributed_tracing_when_tracer_is_disabled
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
