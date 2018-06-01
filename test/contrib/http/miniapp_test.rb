require 'time'
require 'contrib/http/test_helper'
require 'helper'

# ESMiniAppTest tests and shows what you would typically do
# in a custom application, which is already traced. It shows
# how to have HTTP spans be children of application spans.
#
# It uses an ElasticSearch server as a support backend,
# as ES happens to A) serve http and B) be supported with
# a dedicated integration, so it's already there in our CI.
class HTTPMiniAppTest < Minitest::Test
  ELASTICSEARCH_HOST = ENV.fetch('TEST_ELASTICSEARCH_HOST', '127.0.0.1').freeze
  ELASTICSEARCH_PORT = ENV.fetch('TEST_ELASTICSEARCH_PORT', 9200).freeze
  ELASTICSEARCH_SERVER = "http://#{ELASTICSEARCH_HOST}:#{ELASTICSEARCH_PORT}".freeze

  def setup
    Datadog.configure do |c|
      c.tracer hostname: ENV.fetch('TEST_DDAGENT_HOST', 'localhost')
      c.use :http
    end

    # wait until it's really running, docker-compose can be slow
    wait_http_server ELASTICSEARCH_SERVER, 60
  end

  def check_span_page(span)
    assert_equal('page', span.name)
    assert_equal('webapp', span.service)
    assert_equal('/index', span.resource)
    refute_equal(span.trace_id, span.span_id)
    assert_equal(0, span.parent_id)
  end

  def check_span_get(span, parent_id, trace_id)
    assert_equal('http.request', span.name)
    assert_equal('net/http', span.service)
    assert_equal('GET', span.resource)
    assert_equal('_cluster/health', span.get_tag('http.url'))
    assert_equal('GET', span.get_tag('http.method'))
    assert_equal('200', span.get_tag('http.status_code'))
    assert_equal(parent_id, span.parent_id)
    assert_equal(trace_id, span.trace_id)
  end

  def test_miniapp
    client = Net::HTTP.new(ELASTICSEARCH_HOST, ELASTICSEARCH_PORT)

    tracer = get_test_tracer # get a ref to the app tracer
    pin = Datadog::Pin.get_from(client) # get a ref to the HTTP PIN
    pin.tracer = tracer # bind the tracer to the HTTP PIN

    tracer.trace('page') do |span|
      span.service = 'webapp'
      span.resource = '/index'
      2.times do
        response = client.get('_cluster/health')
        refute_nil(response)
      end
    end

    spans = tracer.writer.spans

    # here we should get 3 spans, with spans[2] being the parent
    assert_equal(3, spans.length)
    check_span_page spans[2]
    trace_id = spans[2].trace_id
    parent_id = spans[2].span_id
    check_span_get spans[0], parent_id, trace_id
    check_span_get spans[1], parent_id, trace_id
  end
end
