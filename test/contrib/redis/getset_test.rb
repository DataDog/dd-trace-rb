require 'time'
require 'contrib/redis/test_helper'
require 'helper'

class RedisSetGetTest < Minitest::Test
  REDIS_HOST = '127.0.0.1'.freeze
  REDIS_PORT = 46379
  def setup
    skip unless ENV['TEST_DATADOG_INTEGRATION'] # requires a running agent

    # Here we use the default tracer, on one hand it forces us to have
    # a real agent and checkup the tracer state before / after because its
    # state might be influenced by former tests. OTOH current implementation
    # uses hardcoded Datadog.tracer, so there's no real shortcut.
    @tracer = Datadog.tracer

    @redis = Redis.new(host: REDIS_HOST, port: REDIS_PORT)
  end

  def test_setget
    already_flushed = @tracer.writer.stats[:traces_flushed]
    set_response = @redis.set 'FOO', 'bar'
    assert_equal 'OK', set_response
    get_response = @redis.get 'FOO'
    assert_equal 'bar', get_response
    30.times do
      break if @tracer.writer.stats[:traces_flushed] >= already_flushed + 2
      sleep(0.1)
    end
    assert_equal(already_flushed + 2, @tracer.writer.stats[:traces_flushed])
  end
end
