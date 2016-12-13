require 'time'
require 'contrib/redis/test_helper'
require 'helper'

class RedisSetGetTest < Minitest::Test
  REDIS_HOST = '127.0.0.1'.freeze
  REDIS_PORT = 46379
  def setup
    @tracer = get_test_tracer

    @drivers = {}
    [:ruby, :hiredis].each do |d|
      @drivers[d] = Redis.new(host: REDIS_HOST, port: REDIS_PORT, driver: d)
      pin = Datadog::Pin.get_from(@drivers[d])
      pin.tracer = @tracer
    end
  end

  def check_connect_span(d, span)
    # we don't know when connection is going to happen, when
    # there's a suspicion it happened (typically, one extra span)
    # check the instrumentation is OK with this func.
    assert_equal('redis.connect', span.name)
    assert_equal('redis', span.service)
    assert_equal('127.0.0.1:46379:0', span.resource)
    case d
    when :ruby
      assert_equal('Redis::Connection::Ruby', span.get_tag('redis.driver'))
    when :hiredis
      assert_equal('Redis::Connection::Hiredis', span.get_tag('redis.driver'))
    end
  end

  def check_common_tags(span)
    assert_equal('127.0.0.1', span.get_tag('out.host'))
    assert_equal('46379', span.get_tag('out.port'))
    assert_equal('0', span.get_tag('out.redis_db'))
  end

  def roundtrip_set(d, driver)
    set_response = driver.set 'FOO', 'bar'
    assert_equal 'OK', set_response
    spans = @tracer.writer.spans()
    assert_operator(1, :<=, spans.length)
    check_connect_span(d, spans[0]) if spans.length >= 2
    span = spans[-1]
    check_common_tags(span)
    assert_equal('redis.command', span.name)
    assert_equal('redis', span.service)
    assert_equal('set FOO bar', span.resource)
  end

  def roundtrip_get(_d, driver)
    get_response = driver.get 'FOO'
    assert_equal 'bar', get_response
    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)
    span = spans[0]
    check_common_tags(span)
    assert_equal('redis.command', span.name)
    assert_equal('redis', span.service)
    assert_equal('get FOO', span.resource)
  end

  def test_roundtrip
    @drivers.each do |d, driver|
      roundtrip_set d, driver
      roundtrip_get d, driver
    end
  end

  def test_pipeline
    @drivers.each do |d, driver|
      responses = []
      driver.pipelined do
        responses << driver.set('v1', '0')
        responses << driver.set('v2', '0')
        responses << driver.incr('v1')
        responses << driver.incr('v2')
        responses << driver.incr('v2')
      end
      assert_equal(['OK', 'OK', 1, 1, 2], responses.map(&:value))
      spans = @tracer.writer.spans()
      assert_operator(1, :<=, spans.length)
      check_connect_span(d, spans[0]) if spans.length >= 2
      span = spans[-1]
      check_common_tags(span)
      assert_equal('redis.pipeline', span.name)
      assert_equal('redis', span.service)
      assert_equal("set v1 0\nset v2 0\nincr v1\nincr v2\nincr v2", span.resource)
    end
  end

  def test_error
    @drivers.each do |d, driver|
      begin
        driver.call 'THIS_IS_NOT_A_REDIS_FUNC', 'THIS_IS_NOT_A_VALID_ARG'
      rescue StandardError => e
        assert_kind_of(Redis::CommandError, e)
        assert_equal("ERR unknown command 'THIS_IS_NOT_A_REDIS_FUNC'", e.to_s)
      end
      spans = @tracer.writer.spans()
      assert_operator(1, :<=, spans.length)
      check_connect_span(d, spans[0]) if spans.length >= 2
      span = spans[-1]
      check_common_tags(span)
      assert_equal('redis.command', span.name)
      assert_equal('redis', span.service)
      assert_equal('THIS_IS_NOT_A_REDIS_FUNC THIS_IS_NOT_A_VALID_ARG', span.resource)
      assert_equal(1, span.status, 'this span should be flagged as an error')
      assert_equal("ERR unknown command 'THIS_IS_NOT_A_REDIS_FUNC'", span.get_tag('error.msg'))
      assert_equal('Redis::CommandError', span.get_tag('error.type'))
      assert_operator(3, :<=, span.get_tag('error.stack').length)
    end
  end

  def test_quantize
    @drivers.each do |d, driver|
      driver.set 'K', 'x' * 10000
      response = driver.get 'K'
      assert_equal('x' * 10000, response)
      spans = @tracer.writer.spans()
      assert_operator(2, :<=, spans.length)
      check_connect_span(d, spans[0]) if spans.length >= 3
      span = spans[-2]
      check_common_tags(span)
      assert_equal('redis.command', span.name)
      assert_equal('redis', span.service)
      assert_equal('set K ' + 'x' * 97 + '...', span.resource)
      span = spans[-1]
      check_common_tags(span)
      assert_equal('redis.command', span.name)
      assert_equal('redis', span.service)
      assert_equal('get K', span.resource)
    end
  end
end
