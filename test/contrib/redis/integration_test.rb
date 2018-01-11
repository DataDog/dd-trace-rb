require 'time'
require 'contrib/redis/test_helper'
require 'helper'

class RedisIntegrationTest < Minitest::Test
  REDIS_HOST = '127.0.0.1'.freeze
  REDIS_PORT = 46379
  def setup
    skip unless ENV['TEST_DATADOG_INTEGRATION'] # requires a running agent

    # Here we use the default tracer (to make a real integration test)
    @tracer = Datadog.tracer
    Datadog.configure do |c|
      c.use :redis, tracer: @tracer
    end

    @redis = Redis.new(host: REDIS_HOST, port: REDIS_PORT)
  end

  def test_setget
    sleep(1.5) # make sure there's nothing pending
    already_flushed = @tracer.writer.stats[:traces_flushed]
    set_response = @redis.set 'FOO', 'bar'
    assert_equal 'OK', set_response
    get_response = @redis.get 'FOO'
    assert_equal 'bar', get_response
    try_wait_until(attempts: 30) { @tracer.writer.stats[:traces_flushed] >= already_flushed + 2 }
    assert_operator(already_flushed + 2, :<=, @tracer.writer.stats[:traces_flushed])
  end
end
