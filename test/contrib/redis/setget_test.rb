require 'time'
require 'contrib/redis/test_helper'
require 'helper'

class RedisSetGetTest < Minitest::Test
  REDIS_HOST = '127.0.0.1'.freeze
  REDIS_PORT = 46379
  def setup
    @tracer = get_test_tracer

    @redis = Redis.new(host: REDIS_HOST, port: REDIS_PORT)
    pin = Datadog::Pin.get_from(@redis)
    pin.tracer = @tracer
  end

  def roundtrip_set
    set_response = @redis.set 'FOO', 'bar'
    assert_equal 'OK', set_response
    spans = @tracer.writer.spans()
    assert_equal(2, spans.length)
    span = spans[0]
    assert_equal('redis.connect', span.name)
    assert_equal('redis', span.service)
    assert_equal('127.0.0.1:46379', span.resource)
    span = spans[1]
    assert_equal('redis.command', span.name)
    assert_equal('redis', span.service)
    assert_equal('set FOO bar', span.resource)
  end

  def roundtrip_get
    get_response = @redis.get 'FOO'
    assert_equal 'bar', get_response
    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)
    span = spans[0]
    assert_equal('redis.command', span.name)
    assert_equal('redis', span.service)
    assert_equal('get FOO', span.resource)
  end

  def test_roundtrip
    roundtrip_set
    roundtrip_get
  end
end
