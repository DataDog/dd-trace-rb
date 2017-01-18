require 'time'
require 'contrib/elasticsearch/test_helper'
require 'ddtrace'
require 'helper'
require 'json'

class HTTPRequestTest < Minitest::Test
  ELASTICSEARCH_HOST = '127.0.0.1'.freeze
  ELASTICSEARCH_PORT = 49200
  ELASTICSEARCH_SERVER = ('http://' +
                          HTTPIntegrationTest::ELASTICSEARCH_HOST + ':' +
                          HTTPIntegrationTest::ELASTICSEARCH_PORT.to_s).freeze

  def setup
    @tracer = get_test_tracer

    # wait until it's really running, docker-compose can be slow
    wait_http_server 'http://' + ELASTICSEARCH_HOST + ':' + ELASTICSEARCH_PORT.to_s, 60

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
    assert_equal('_cluster/health', span.resource)
    assert_nil(span.get_tag('http.url'))
    assert_equal('GET', span.get_tag('http.method'))
    assert_equal('200', span.get_tag('http.status_code'))
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
    assert_equal('/my/thing/42', span.resource)
    assert_nil(span.get_tag('http.url'))
    assert_equal('POST', span.get_tag('http.method'))
  end

  def test_404
    response = @client.get('/admin.php?user=admin&passwd=123456')
    assert_equal('404', response.code, 'bad response status')
    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)
    span = spans[0]
    assert_equal('http.request', span.name)
    assert_equal('net/http', span.service)
    assert_equal('/admin.php?user=admin&passwd=123456', span.resource)
    assert_nil(span.get_tag('http.url'))
    assert_equal('GET', span.get_tag('http.method'))
    assert_equal('404', span.get_tag('http.status_code'))
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
      assert_equal('/_cluster/health', span.resource)
      assert_nil(span.get_tag('http.url'))
      assert_equal('GET', span.get_tag('http.method'))
      assert_equal('200', span.get_tag('http.status_code'))
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
end
