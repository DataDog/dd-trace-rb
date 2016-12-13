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

  def check_span_command1(span, parent_id, trace_id)
    assert_equal('redis.command', span.name)
    assert_equal('redis', span.service)
    assert_equal('get data1', span.resource)
    assert_equal(parent_id, span.parent_id)
    assert_equal(trace_id, span.trace_id)
  end

  def check_span_command2(span, parent_id, trace_id)
    assert_equal('redis.command', span.name)
    assert_equal('redis', span.service)
    assert_equal("set data2 something\nget data2", span.resource)
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
      redis.get 'data1'
      redis.pipelined do
        redis.set 'data2', 'something'
        redis.get 'data2'
      end
    end

    spans = tracer.writer.spans

    # here we should get 3 spans, with spans[2] being the parent of others
    assert_equal(3, spans.length)
    check_span_publish spans[2]
    trace_id = spans[2].span_id
    check_span_command2 spans[1], trace_id, trace_id
    check_span_command1 spans[0], trace_id, trace_id
  end
end
