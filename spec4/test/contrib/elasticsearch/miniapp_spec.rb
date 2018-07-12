require('time')
require('contrib/elasticsearch/test_helper')
require('helper')
class ESMiniAppTest < Minitest::Test
  ELASTICSEARCH_HOST = ENV.fetch('TEST_ELASTICSEARCH_HOST', '127.0.0.1').freeze
  ELASTICSEARCH_PORT = ENV.fetch('TEST_ELASTICSEARCH_PORT', '9200').freeze
  ELASTICSEARCH_SERVER = "http://#{ELASTICSEARCH_HOST}:#{ELASTICSEARCH_PORT}".freeze
  before do
    Datadog.configure { |c| c.use(:elasticsearch) }
    wait_http_server(ELASTICSEARCH_SERVER, 60)
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
  it('miniapp') do
    client = Elasticsearch::Client.new(url: ELASTICSEARCH_SERVER)
    tracer = get_test_tracer
    pin = Datadog::Pin.get_from(client)
    pin.tracer = tracer
    tracer.trace('publish') do |span|
      span.service = 'webapp'
      span.resource = '/status'
      response = client.perform_request('GET', '_cluster/health')
      expect(response.status).to(eq(200))
      response = client.perform_request('GET', '_cluster/health')
      expect(response.status).to(eq(200))
    end
    spans = tracer.writer.spans
    expect(spans.length).to(eq(3))
    check_span_publish(spans[2])
    trace_id = spans[2].trace_id
    parent_id = spans[2].span_id
    check_span_command(spans[1], parent_id, trace_id)
    check_span_command(spans[0], parent_id, trace_id)
  end
end
