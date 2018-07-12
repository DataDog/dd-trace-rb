require('time')
require('contrib/elasticsearch/test_helper')
require('helper')
class ESIntegrationTest < Minitest::Test
  ELASTICSEARCH_HOST = ENV.fetch('TEST_ELASTICSEARCH_HOST', '127.0.0.1').freeze
  ELASTICSEARCH_PORT = ENV.fetch('TEST_ELASTICSEARCH_PORT', '9200').freeze
  ELASTICSEARCH_SERVER = "http://#{ELASTICSEARCH_HOST}:#{ELASTICSEARCH_PORT}".freeze
  before do
    skip unless ENV['TEST_DATADOG_INTEGRATION']
    Datadog.configure do |c|
      c.tracer(hostname: ENV.fetch('TEST_DDAGENT_HOST', 'localhost'))
      c.use(:elasticsearch)
    end
    @tracer = Datadog.tracer
    wait_http_server(ELASTICSEARCH_SERVER, 60)
    @client = Elasticsearch::Client.new(url: ELASTICSEARCH_SERVER)
  end
  it('perform request') do
    sleep(1.5)
    already_flushed = @tracer.writer.stats[:traces_flushed]
    response = @client.perform_request('GET', '_cluster/health')
    expect(response.status).to(eq(200))
    30.times do
      break if @tracer.writer.stats[:traces_flushed] >= (already_flushed + 1)
      sleep(0.1)
    end
    expect(@tracer.writer.stats[:traces_flushed]).to(eq((already_flushed + 1)))
  end
end
