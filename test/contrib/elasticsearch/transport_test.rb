require 'helper'
require 'contrib/elasticsearch/test_helper'
require 'ddtrace/contrib/elasticsearch/core'

class ESTracingTest < Minitest::Test
  def setup
    @tracer = get_test_tracer
    client = Elasticsearch::Client.new
    @client = client
  end

  def test_perform_request
    response = @client.perform_request 'GET', '_cluster/health'
    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)
  end

end
