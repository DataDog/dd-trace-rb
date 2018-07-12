require('time')
require('contrib/elasticsearch/test_helper')
require('helper')
class HTTPIntegrationTest < Minitest::Test
  ELASTICSEARCH_HOST = ENV.fetch('TEST_ELASTICSEARCH_HOST', '127.0.0.1').freeze
  ELASTICSEARCH_PORT = ENV.fetch('TEST_ELASTICSEARCH_PORT', '9200').freeze
  ELASTICSEARCH_SERVER = "http://#{ELASTICSEARCH_HOST}:#{ELASTICSEARCH_PORT}".freeze
  before do
    skip unless ENV['TEST_DATADOG_INTEGRATION']
    Datadog.configure do |c|
      c.tracer(hostname: ENV.fetch('TEST_DDAGENT_HOST', 'localhost'))
      c.use(:http)
    end
    @tracer = Datadog.tracer
    wait_http_server(ELASTICSEARCH_SERVER, 60)
  end
  it('request') do
    sleep(1.5)
    already_flushed = @tracer.writer.stats[:traces_flushed]
    content = Net::HTTP.get(URI((ELASTICSEARCH_SERVER + '/_cluster/health')))
    assert_kind_of(String, content)
    30.times do
      break if @tracer.writer.stats[:traces_flushed] >= (already_flushed + 1)
      sleep(0.1)
    end
    expect(@tracer.writer.stats[:traces_flushed]).to(eq((already_flushed + 1)))
  end
  it('block call') do
    sleep(1.5)
    already_flushed = @tracer.writer.stats[:traces_flushed]
    Net::HTTP.start(ELASTICSEARCH_HOST, ELASTICSEARCH_PORT.to_i) do |http|
      request = Net::HTTP::Get.new(ELASTICSEARCH_SERVER)
      response = http.request(request)
      assert_kind_of(Net::HTTPResponse, response)
      request = Net::HTTP::Get.new(ELASTICSEARCH_SERVER)
      response = http.request(request)
      assert_kind_of(Net::HTTPResponse, response)
    end
    30.times do
      break if @tracer.writer.stats[:traces_flushed] >= (already_flushed + 1)
      sleep(0.1)
    end
    expect(@tracer.writer.stats[:traces_flushed]).to(eq((already_flushed + 2)))
  end
end
