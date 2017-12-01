ENV['REDIS_URL'] = 'redis://127.0.0.1:46379'

# It's important that there's *NO* "require 'redis-rails'" or
# even "require 'redis'" here. Because people using Rails do not
# include those headers themselves, instead they rely on the
# framework to do it for them. So it should work smoothly without
# including anything.

require 'helper'
require 'contrib/rails/test_helper'

class RedisCacheTracingTest < ActionController::TestCase
  setup do
    # switch Rails with a dummy tracer
    @original_tracer = Datadog.configuration[:rails][:tracer]
    @tracer = get_test_tracer()
    Datadog.configuration[:rails][:tracer] = @tracer
    Datadog.configuration.use(:redis)

    # get the Redis pin accessing private methods (only Rails 3.x)
    client = Rails.cache.instance_variable_get(:@data)
    pin = Datadog::Pin.get_from(client)
    refute_nil(pin, 'unable to get pin from Redis connection')
    pin.tracer = @tracer
  end

  teardown do
    Datadog.configuration[:rails][:tracer] = @original_tracer
  end

  test 'cache.read() and cache.fetch() are properly traced' do
    # read and fetch should behave exactly the same, and we shall
    # never see a read() having a fetch() as parent.
    [:read, :fetch].each do |f|
      # use the cache and assert the proper span
      Rails.cache.write('custom-key', 50)
      value = Rails.cache.send(f, 'custom-key')
      assert_equal(50, value)

      spans = @tracer.writer.spans()
      assert_equal(spans.length, 4)
      cache, _, redis, = spans
      assert_equal(cache.name, 'rails.cache')
      assert_equal(cache.span_type, 'cache')
      assert_equal(cache.resource, 'GET')
      assert_equal(cache.service, 'rails-cache')
      assert_equal(cache.get_tag('rails.cache.backend').to_s, 'redis_store')
      assert_equal(cache.get_tag('rails.cache.key'), 'custom-key')

      assert_equal(redis.name, 'redis.command')
      assert_equal(redis.span_type, 'redis')
      assert_equal(redis.resource, 'GET custom-key')
      assert_equal(redis.get_tag('redis.raw_command'), 'GET custom-key')
      assert_equal(redis.service, 'redis')
      # the following ensures span will be correctly displayed (parent/child of the same trace)
      assert_equal(cache.trace_id, redis.trace_id)
      assert_equal(cache.span_id, redis.parent_id)
    end
  end

  test 'cache.fetch() is properly traced and handles blocks' do
    Rails.cache.delete('custom-key')
    @tracer.writer.spans() # empty spans

    # value does not exist, fetch should both store it and return it
    value = Rails.cache.fetch('custom-key') do
      51
    end
    assert_equal(51, value)

    spans = @tracer.writer.spans()
    assert_equal(4, spans.length)

    cache_get, cache_set, redis_get, redis_set = spans

    assert_equal(cache_set.name, 'rails.cache')
    assert_equal(cache_set.resource, 'SET')
    assert_equal(redis_set.name, 'redis.command')
    assert_equal(cache_get.name, 'rails.cache')
    assert_equal(cache_get.resource, 'GET')
    assert_equal(redis_get.name, 'redis.command')

    # check that the value is really updated, and persistent
    value = Rails.cache.read('custom-key')
    @tracer.writer.spans() # empty spans
    assert_equal(value, 51)

    # if value exists, fetch returns it and does no update
    value = Rails.cache.fetch('custom-key') do
      52
    end
    assert_equal(51, value)

    spans = @tracer.writer.spans()
    assert_equal(2, spans.length)

    cache, redis = spans
    assert_equal(cache.name, 'rails.cache')
    assert_equal(redis.name, 'redis.command')
  end

  test 'cache.write() is properly traced' do
    # use the cache and assert the proper span
    Rails.cache.write('custom-key', 50)
    spans = @tracer.writer.spans()
    assert_equal(spans.length, 2)
    cache, redis = spans

    assert_equal(cache.name, 'rails.cache')
    assert_equal(cache.span_type, 'cache')
    assert_equal(cache.resource, 'SET')
    assert_equal(cache.service, 'rails-cache')
    assert_equal(cache.get_tag('rails.cache.backend').to_s, 'redis_store')
    assert_equal(cache.get_tag('rails.cache.key'), 'custom-key')

    assert_equal(redis.name, 'redis.command')
    assert_equal(redis.span_type, 'redis')
    assert_match(/SET custom-key .*ActiveSupport.*/, redis.resource)
    assert_match(/SET custom-key .*ActiveSupport.*/, redis.get_tag('redis.raw_command'))
    assert_equal(redis.service, 'redis')
    # the following ensures span will be correctly displayed (parent/child of the same trace)
    assert_equal(cache.trace_id, redis.trace_id)
    assert_equal(cache.span_id, redis.parent_id)
  end

  test 'cache.delete() is properly traced' do
    # use the cache and assert the proper span
    Rails.cache.delete('custom-key')
    spans = @tracer.writer.spans()
    assert_equal(spans.length, 2)
    cache, del = spans

    assert_equal(cache.name, 'rails.cache')
    assert_equal(cache.span_type, 'cache')
    assert_equal(cache.resource, 'DELETE')
    assert_equal(cache.service, 'rails-cache')
    assert_equal(cache.get_tag('rails.cache.backend').to_s, 'redis_store')
    assert_equal(cache.get_tag('rails.cache.key'), 'custom-key')

    assert_equal(del.name, 'redis.command')
    assert_equal(del.span_type, 'redis')
    assert_equal(del.resource, 'DEL custom-key')
    assert_equal(del.get_tag('redis.raw_command'), 'DEL custom-key')
    assert_equal(del.service, 'redis')
    # the following ensures span will be correctly displayed (parent/child of the same trace)
    assert_equal(cache.trace_id, del.trace_id)
    assert_equal(cache.span_id, del.parent_id)
  end
end
