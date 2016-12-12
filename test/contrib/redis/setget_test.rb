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

  def check_connect_span(span)
    # we don't know when connection is going to happen, when
    # there's a suspicion it happened (typically, one extra span)
    # check the instrumentation is OK with this func.
    assert_equal('redis.connect', span.name)
    assert_equal('redis', span.service)
    assert_equal('127.0.0.1:46379', span.resource)
  end

  def roundtrip_set
    set_response = @redis.set 'FOO', 'bar'
    assert_equal 'OK', set_response
    spans = @tracer.writer.spans()
    assert_operator(1, :<=, spans.length)
    check_connect_span(spans[0]) if spans.length >= 2
    span = spans[-1]
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

  def test_pipeline
    responses = []
    @redis.pipelined do
      responses << @redis.set('v1', '0')
      responses << @redis.set('v2', '0')
      responses << @redis.incr('v1')
      responses << @redis.incr('v2')
      responses << @redis.incr('v2')
    end
    assert_equal(['OK', 'OK', 1, 1, 2], responses.map(&:value))
    spans = @tracer.writer.spans()
    assert_operator(1, :<=, spans.length)
    check_connect_span(spans[0]) if spans.length >= 2
    span = spans[-1]
    assert_equal('redis.pipeline', span.name)
    assert_equal('redis', span.service)
    assert_equal("set v1 0\nset v2 0\nincr v1\nincr v2\nincr v2", span.resource)
  end
end
