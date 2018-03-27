require 'time'
require 'contrib/elasticsearch/test_helper'
require 'ddtrace'
require 'helper'

class ESTransportTest < Minitest::Test
  ELASTICSEARCH_SERVER = 'http://127.0.0.1:49200'.freeze
  def setup
    Datadog.configure do |c|
      c.use :elasticsearch
    end

    @tracer = get_test_tracer

    # wait until it's really running, docker-compose can be slow
    wait_http_server ELASTICSEARCH_SERVER, 60

    @client = Elasticsearch::Client.new url: ELASTICSEARCH_SERVER
    pin = Datadog::Pin.get_from(@client)
    pin.tracer = @tracer
  end

  def teardown
    @client.perform_request 'DELETE', '*'
  end

  def test_perform_request
    response = @client.perform_request 'GET', '_cluster/health'
    assert_equal(200, response.status, 'bad response status')
    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)
    span = spans[0]
    assert_equal('elasticsearch.query', span.name)
    assert_equal('elasticsearch', span.service)
    assert_equal('GET _cluster/health', span.resource)
    assert_equal('_cluster/health', span.get_tag('elasticsearch.url'))
    assert_equal('GET', span.get_tag('elasticsearch.method'))
    assert_equal('200', span.get_tag('http.status_code'))
    assert_nil(span.get_tag('elasticsearch.params'))
    assert_nil(span.get_tag('elasticsearch.body'))
    assert_equal('127.0.0.1', span.get_tag('out.host'))
    assert_equal('49200', span.get_tag('out.port'))
  end

  def test_perform_request_with_encoded_body
    response = @client.perform_request 'PUT', '/my/thing/1', { refresh: true }, '{"data1":"D1","data2":"D2"}'
    assert_equal(201, response.status, 'bad response status')
    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)
    span = spans[0]
    assert_equal('elasticsearch.query', span.name)
    assert_equal('elasticsearch', span.service)
    assert_equal('PUT /my/thing/?', span.resource)
    assert_equal('/my/thing/1', span.get_tag('elasticsearch.url'))
    assert_equal('PUT', span.get_tag('elasticsearch.method'))
    assert_equal('201', span.get_tag('http.status_code'))
    assert_equal("{\"refresh\":true\}", span.get_tag('elasticsearch.params'))
    assert_equal('{"data1":"?","data2":"?"}', span.get_tag('elasticsearch.body'))
  end

  def roundtrip_put
    response = @client.perform_request 'PUT', '/my/thing/1', { refresh: true }, data1: 'D1', data2: 'D2'
    assert_equal(201, response.status, 'bad response status')
    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)
    span = spans[0]
    assert_equal('elasticsearch.query', span.name)
    assert_equal('elasticsearch', span.service)
    assert_equal('PUT /my/thing/?', span.resource)
    assert_equal('/my/thing/1', span.get_tag('elasticsearch.url'))
    assert_equal('PUT', span.get_tag('elasticsearch.method'))
    assert_equal('201', span.get_tag('http.status_code'))
    assert_equal("{\"refresh\":true\}", span.get_tag('elasticsearch.params'))
    assert_equal('{"data1":"?","data2":"?"}', span.get_tag('elasticsearch.body'))
  end

  def roundtrip_get
    response = @client.perform_request 'GET', '/my/thing/1'
    assert_equal(200, response.status, 'bad response status')
    body = response.body
    assert_kind_of(Hash, body, 'bad response body')
    assert_equal('my', body['_index'])
    assert_equal('thing', body['_type'])
    assert_equal('1', body['_id'])
    assert_equal(true, body['found'])
    assert_equal({ 'data1' => 'D1', 'data2' => 'D2' }, body['_source'])
    spans = @tracer.writer.spans()
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

  def test_roundtrip
    roundtrip_put
    roundtrip_get
  end

  def test_pin_override
    pin = Datadog::Pin.get_from(@client)
    pin.service = 'bar'
    response = @client.perform_request 'GET', '_cluster/health'
    assert_equal(200, response.status, 'bad response status')
    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)
    span = spans[0]
    assert_equal('elasticsearch.query', span.name)
    assert_equal('bar', span.service)
  end
end
