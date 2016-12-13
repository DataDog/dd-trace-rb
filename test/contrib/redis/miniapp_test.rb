require 'time'
require 'contrib/redis/test_helper'
require 'helper'

class RedisMiniAppTest < Minitest::Test
  REDIS_HOST = '127.0.0.1'.freeze
  REDIS_PORT = 46379

  def check_span_publish(span)
    assert_equal('publish', span.name)
    assert_equal('webapp', span.service)
    assert_equal('/index', span.resource)
    assert_equal(span.trace_id, span.span_id)
    assert_equal(0, span.parent_id)
  end

  def check_span_connect(span, parent_id, trace_id)
    assert_equal('redis.connect', span.name)
    assert_equal('redis', span.service)
    assert_equal('127.0.0.1:46379:0', span.resource)
    assert_equal(parent_id, span.parent_id)
    assert_equal(trace_id, span.trace_id)
  end

  def check_span_command(span, parent_id, trace_id)
    assert_equal('redis.command', span.name)
    assert_equal('redis', span.service)
    assert_equal('get data', span.resource)
    assert_equal(parent_id, span.parent_id)
    assert_equal(trace_id, span.trace_id)
  end

  def test_miniapp
    redis = Redis.new(host: REDIS_HOST, port: REDIS_PORT)

    # now this is how you make sure that the redis spans are sub-spans
    # of the apps parent spans:
    tracer = get_test_tracer # get a ref to the app tracer
    pin = Datadog::Pin.get_from(redis) # get a ref to the redis PIN
    pin.tracer = tracer                # bind the tracer to the redis PIN

    tracer.trace('publish') do |span|
      span.service = 'webapp'
      span.resource = '/index'
      redis.get 'data'
    end

    spans = tracer.writer.spans

    # here we should get 3 spans, with spans[0] child of spans[1] child of spans[2]
    assert_equal(3, spans.length)
    check_span_publish spans[2]
    check_span_command spans[1], spans[2].span_id, spans[2].span_id
    check_span_connect spans[0], spans[1].span_id, spans[2].span_id
  end
end
