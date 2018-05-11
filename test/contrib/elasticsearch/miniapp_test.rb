require 'time'
require 'contrib/elasticsearch/test_helper'
require 'helper'

# ESMiniAppTest tests and shows what you would typically do
# in a custom application, which is already traced. It shows
# how to have ES spans be children of application spans.
class ESMiniAppTest < Minitest::Test
  ELASTICSEARCH_HOST = ENV.fetch('TEST_ELASTICSEARCH_HOST', '127.0.0.1').freeze
  ELASTICSEARCH_PORT = ENV.fetch('TEST_ELASTICSEARCH_PORT', '9200').freeze
  ELASTICSEARCH_SERVER = "http://#{ELASTICSEARCH_HOST}:#{ELASTICSEARCH_PORT}".freeze

  def setup
    Datadog.configure do |c|
      c.use :elasticsearch
    end

    # wait until it's really running, docker-compose can be slow
    wait_http_server ELASTICSEARCH_SERVER, 60
  end

  def check_span_publish(span)
    assert_equal('publish', span.name)
    assert_equal('webapp', span.service)
    assert_equal('/status', span.resource)
    refute_equal(span.trace_id, span.span_id)
    assert_equal(0, span.parent_id)
  end

  def check_span_command(span, parent_id, trace_id)
    assert_equal('elasticsearch.query', span.name)
    assert_equal('elasticsearch', span.service)
    assert_equal('GET _cluster/health', span.resource)
    assert_equal(parent_id, span.parent_id)
    assert_equal(trace_id, span.trace_id)
  end

  def test_miniapp
    client = Elasticsearch::Client.new url: ELASTICSEARCH_SERVER

    # now this is how you make sure that the ES spans are sub-spans
    # of the apps parent spans:
    tracer = get_test_tracer # get a ref to the app tracer
    pin = Datadog::Pin.get_from(client) # get a ref to the ES PIN
    pin.tracer = tracer # bind the tracer to the ES PIN

    tracer.trace('publish') do |span|
      span.service = 'webapp'
      span.resource = '/status'
      response = client.perform_request 'GET', '_cluster/health'
      assert_equal(200, response.status, 'bad response status')
      response = client.perform_request 'GET', '_cluster/health'
      assert_equal(200, response.status, 'bad response status')
    end

    spans = tracer.writer.spans

    # here we should get 3 spans, with spans[2] being the parent
    assert_equal(3, spans.length)
    check_span_publish spans[2]
    trace_id = spans[2].trace_id
    parent_id = spans[2].span_id
    check_span_command spans[1], parent_id, trace_id
    check_span_command spans[0], parent_id, trace_id
  end
end
