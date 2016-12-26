require 'time'
require 'contrib/elasticsearch/test_helper'
require 'helper'

class ESIntegrationTest < Minitest::Test
  ELASTICSEARCH_SERVER = 'http://127.0.0.1:49200'.freeze
  def setup
    skip unless ENV['TEST_DATADOG_INTEGRATION'] # requires a running agent

    # Here we use the default tracer (to make a real integration test)
    @tracer = Datadog.tracer

    # wait until it's really running, docker-compose can be slow
    wait_http_server ELASTICSEARCH_SERVER, 60
    client = Elasticsearch::Client.new url: ELASTICSEARCH_SERVER
    @client = client
  end

  def test_perform_request
    sleep(1.5) # make sure there's nothing pending
    already_flushed = @tracer.writer.stats[:traces_flushed]
    response = @client.perform_request 'GET', '_cluster/health'
    assert_equal(200, response.status, 'bad response status')
    30.times do
      break if @tracer.writer.stats[:traces_flushed] >= already_flushed + 1
      sleep(0.1)
    end
    assert_equal(already_flushed + 1, @tracer.writer.stats[:traces_flushed])
  end
end
