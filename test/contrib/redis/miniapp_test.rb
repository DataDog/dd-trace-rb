require 'time'
require 'contrib/redis/test_helper'
require 'helper'

# RedisMiniAppTest tests and shows what you would typically do
# in a custom application, which is already traced. It shows
# how to have Redis spans be children of application spans.
class RedisMiniAppTest < Minitest::Test
  REDIS_HOST = '127.0.0.1'.freeze
  REDIS_PORT = 46379

  def check_span_publish(span)
    assert_equal('publish', span.name)
    assert_equal('webapp', span.service)
    assert_equal('/index', span.resource)
    refute_equal(span.trace_id, span.span_id)
    assert_equal(0, span.parent_id)
  end

  def check_span_process(span, parent_id, trace_id)
    assert_equal('process', span.name)
    assert_equal('datalayer', span.service)
    assert_equal('home', span.resource)
    assert_equal(parent_id, span.parent_id)
    assert_equal(trace_id, span.trace_id)
  end

  def check_span_command(span, parent_id, trace_id)
    assert_equal('redis.command', span.name)
    assert_equal('redis', span.service)
    assert_equal(parent_id, span.parent_id)
    assert_equal(trace_id, span.trace_id)
  end

  def test_miniapp
    redis = Redis.new(host: REDIS_HOST, port: REDIS_PORT)

    # now this is how you make sure that the redis spans are sub-spans
    # of the apps parent spans:
    tracer = get_test_tracer # get a ref to the app tracer
    Datadog.configure(client_from_driver(redis), tracer: tracer)

    tracer.trace('publish') do |span|
      span.service = 'webapp'
      span.resource = '/index'
      tracer.trace('process') do |subspan|
        subspan.service = 'datalayer'
        subspan.resource = 'home'
        redis.get 'data1'
        redis.pipelined do
          redis.set 'data2', 'something'
          redis.get 'data2'
        end
      end
    end

    spans = tracer.writer.spans

    # here we should get 4 spans, with :
    # spans[3] being the parent of span[2]
    # spand[2] being the parant of span[0] and span[1]
    assert_equal(4, spans.length)
    process, publish, redis_cmd1, redis_cmd2 = spans
    check_span_publish publish
    parent_id = publish.span_id
    trace_id = publish.trace_id
    check_span_process process, parent_id, trace_id
    parent_id = process.span_id
    check_span_command redis_cmd1, parent_id, trace_id
    check_span_command redis_cmd2, parent_id, trace_id
  end

  def client_from_driver(driver)
    if Gem::Version.new(::Redis::VERSION) >= Gem::Version.new('4.0.0')
      driver._client
    else
      driver.client
    end
  end
end
