require 'time'
require 'contrib/redis/test_helper'
require 'helper'

class RedisTest < Minitest::Test
  REDIS_HOST = '127.0.0.1'.freeze
  REDIS_PORT = 46379
  def setup
    @tracer = get_test_tracer()

    @drivers = {}
    [:ruby, :hiredis].each do |d|
      @drivers[d] = Redis.new(host: REDIS_HOST, port: REDIS_PORT, driver: d)
      pin = Datadog::Pin.get_from(@drivers[d])
      pin.tracer = @tracer
    end
  end

  def check_common_tags(span)
    assert_equal('127.0.0.1', span.get_tag('out.host'))
    assert_equal('46379', span.get_tag('out.port'))
    assert_equal('0', span.get_tag('out.redis_db'))
  end

  def roundtrip_set(driver, service)
    set_response = driver.set 'FOO', 'bar'
    assert_equal 'OK', set_response
    spans = @tracer.writer.spans()
    assert_operator(1, :<=, spans.length)
    span = spans[-1]
    check_common_tags(span)
    assert_equal('redis.command', span.name)
    assert_equal(service, span.service)
    assert_equal('SET FOO bar', span.resource)
    assert_equal('SET FOO bar', span.get_tag('redis.raw_command'))
  end

  def roundtrip_get(driver, service)
    get_response = driver.get 'FOO'
    assert_equal 'bar', get_response
    spans = @tracer.writer.spans()
    assert_equal(1, spans.length)
    span = spans[0]
    check_common_tags(span)
    assert_equal('redis.command', span.name)
    assert_equal(service, span.service)
    assert_equal('GET FOO', span.resource)
    assert_equal('GET FOO', span.get_tag('redis.raw_command'))
  end

  def test_roundtrip
    @drivers.each do |_d, driver|
      pin = Datadog::Pin.get_from(driver)
      refute_nil(pin)
      assert_equal('db', pin.app_type)
      roundtrip_set driver, 'redis'
      roundtrip_get driver, 'redis'
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
      assert_equal(5, span.get_metric('redis.pipeline_length'))
      assert_equal('redis.command', span.name)
      assert_equal('redis', span.service)
      assert_equal("SET v1 0\nSET v2 0\nINCR v1\nINCR v2\nINCR v2", span.resource)
      assert_equal("SET v1 0\nSET v2 0\nINCR v1\nINCR v2\nINCR v2", span.get_tag('redis.raw_command'))
    end
  end

  def test_error
    @drivers.each do |_d, driver|
      begin
        driver.call 'THIS_IS_NOT_A_REDIS_FUNC', 'THIS_IS_NOT_A_VALID_ARG'
      rescue StandardError => e
        assert_kind_of(Redis::CommandError, e)
        assert_equal("ERR unknown command 'THIS_IS_NOT_A_REDIS_FUNC'", e.to_s)
      end
      spans = @tracer.writer.spans()
      assert_operator(1, :<=, spans.length)
      span = spans[-1]
      check_common_tags(span)
      assert_equal('redis.command', span.name)
      assert_equal('redis', span.service)
      assert_equal('THIS_IS_NOT_A_REDIS_FUNC THIS_IS_NOT_A_VALID_ARG', span.resource)
      assert_equal('THIS_IS_NOT_A_REDIS_FUNC THIS_IS_NOT_A_VALID_ARG', span.get_tag('redis.raw_command'))
      assert_equal(1, span.status, 'this span should be flagged as an error')
      assert_equal("ERR unknown command 'THIS_IS_NOT_A_REDIS_FUNC'", span.get_tag('error.msg'))
      assert_equal('Redis::CommandError', span.get_tag('error.type'))
      assert_operator(3, :<=, span.get_tag('error.stack').length)
    end
  end

  def test_quantize
    @drivers.each do |_d, driver|
      driver.set 'K', 'x' * 500
      response = driver.get 'K'
      assert_equal('x' * 500, response)
      spans = @tracer.writer.spans()
      assert_operator(2, :<=, spans.length)
      get, set = spans[-2..-1]
      check_common_tags(set)
      assert_equal('redis.command', set.name)
      assert_equal('redis', set.service)
      assert_equal('SET K ' + 'x' * 47 + '...', set.resource)
      assert_equal('SET K ' + 'x' * 47 + '...', set.get_tag('redis.raw_command'))
      check_common_tags(get)
      assert_equal('redis.command', get.name)
      assert_equal('redis', get.service)
      assert_equal('GET K', get.resource)
      assert_equal('GET K', get.get_tag('redis.raw_command'))
    end
  end

  def test_service_name
    service_name = 'test'
    driver = Redis.new(host: REDIS_HOST, port: REDIS_PORT, driver: :ruby)
    pin = Datadog::Pin.get_from(driver)
    pin.tracer = @tracer
    pin.service = service_name
    @tracer.writer.services() # empty queue
    @tracer.set_service_info("redis-#{service_name}", 'redis', Datadog::Ext::AppTypes::CACHE)
    driver.set 'FOO', 'bar'
    services = @tracer.writer.services
    assert_equal(1, services.length)
    assert_equal({ 'app' => 'redis', 'app_type' => 'cache' }, services['redis-test'])
  end
end
