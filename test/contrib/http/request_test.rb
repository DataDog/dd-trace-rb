require 'time'
require 'contrib/elasticsearch/test_helper'
require 'ddtrace'
require 'helper'

class HTTPRequestTest < Minitest::Test
  ELASTICSEARCH_HOST = '127.0.0.1'.freeze
  ELASTICSEARCH_PORT = 49200

  def setup
    @tracer = get_test_tracer

    # wait until it's really running, docker-compose can be slow
    wait_http_server 'http://' + ELASTICSEARCH_HOST + ':' + ELASTICSEARCH_PORT.to_s, 60

    @client = Net::HTTP.new(ELASTICSEARCH_HOST, ELASTICSEARCH_PORT)
    pin = Datadog::Pin.get_from(@client)
    pin.tracer = @tracer
  end

  def test_basic_request
    return
    response = @client.get('_cluster/health')
    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)
    span = spans[0]
    assert_equal('elasticsearch.query', span.name)
    assert_equal('elasticsearch', span.service)
    assert_equal('GET _cluster/health', span.resource)
    assert_equal('_cluster/health', span.get_tag('elasticsearch.url'))
    assert_equal('GET', span.get_tag('elasticsearch.method'))
    assert_nil(span.get_tag('elasticsearch.params'))
    assert_nil(span.get_tag('elasticsearch.body'))
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
