require 'time'
require 'contrib/elasticsearch/test_helper'
require 'ddtrace'
require 'helper'

class ESTransportTest < Minitest::Test
  ELASTICSEARCH_SERVER = 'http://127.0.0.1:49200'.freeze
  def setup
    @tracer = get_test_tracer

    # wait until it's really running, docker-compose can be slow
    wait_http_server ELASTICSEARCH_SERVER, 60

    @client = Elasticsearch::Client.new url: ELASTICSEARCH_SERVER
    pin = Datadog::Pin.get_from(@client)
    pin.tracer = @tracer
  end

  def test_perform_request
    response = @client.perform_request 'GET', '_cluster/health'
    assert_equal(200, response.status, 'bad response status')
    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)
    span=spans[0]
    assert_equal('elasticsearch.query', span.name)
    assert_equal('elasticsearch', span.service)
    assert_equal('GET _cluster/health',span.resource)
    assert_equal('GET',span.get_tag('elasticsearch.method'))
    assert_equal('_cluster/health',span.get_tag('elasticsearch.url'))
  end
end
