require 'time'
require 'helper'
require 'contrib/elasticsearch/test_helper'
require 'ddtrace/contrib/elasticsearch/core'

class ESTracingTest < Minitest::Test
  def setup
    skip unless ENV['TEST_DATADOG_INTEGRATION'] # requires a running agent

    # Here we use the default tracer, on one hand it forces us to have
    # a real agent and checkup the tracer state before / after because its
    # state might be influenced by former tests. OTOH current implementation
    # uses hardcoded Datadog.tracer, so there's no real shortcut.
    @tracer = Datadog.tracer
    client = Elasticsearch::Client.new url: 'http://127.0.0.1:49200'
    @client = client
  end

  def test_perform_request
    already_flushed = @tracer.writer.stats[:traces_flushed]
    response = @client.perform_request 'GET', '_cluster/health'
    30.times do
      break if @tracer.writer.stats[:traces_flushed] >= already_flushed + 1
      sleep(0.1)
    end
    assert_equal(200, response.status, 'bad response status')
    assert_equal(already_flushed + 1, @tracer.writer.stats[:traces_flushed])
  end
end
