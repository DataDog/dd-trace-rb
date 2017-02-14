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
    @original_tracer = Rails.configuration.datadog_trace[:tracer]
    @tracer = get_test_tracer()
    Rails.configuration.datadog_trace[:tracer] = @tracer
    assert_equal(true, Rails.cache.respond_to?(:data), "cache '#{Rails.cache}' has no data")
    pin = Datadog::Pin.get_from(Rails.cache.data)
    refute_nil(pin, 'unable to get pin from Redis connection')
    pin.tracer = @tracer
  end

  teardown do
    Rails.configuration.datadog_trace[:tracer] = @original_tracer
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
      span = spans[-1]
      assert_equal(span.name, 'rails.cache')
      assert_equal(span.span_type, 'cache')
      assert_equal(span.resource, 'GET')
      assert_equal(span.service, 'rails-cache')
      assert_equal(span.get_tag('rails.cache.backend').to_s, 'redis_store')
      assert_equal(span.get_tag('rails.cache.key'), 'custom-key')
      span = spans[-2]
      assert_equal(span.name, 'redis.command')
      assert_equal(span.span_type, 'redis')
      assert_equal(span.resource, 'get custom-key')
      assert_equal(span.service, 'redis')
      # the following ensures span will be correctly displayed (parent/child of the same trace)
      assert_equal(spans[-1].trace_id, spans[-2].trace_id)
      assert_equal(spans[-1].span_id, spans[-2].parent_id)
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

    assert_equal(spans[-1].name, 'rails.cache')
    assert_equal(spans[-1].resource, 'SET')
    assert_equal(spans[-2].name, 'redis.command')
    assert_equal(spans[-3].name, 'rails.cache')
    assert_equal(spans[-3].resource, 'GET')
    assert_equal(spans[-4].name, 'redis.command')

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

    assert_equal(spans[-1].name, 'rails.cache')
    assert_equal(spans[-2].name, 'redis.command')
  end

  test 'cache.write() is properly traced' do
    # use the cache and assert the proper span
    Rails.cache.write('custom-key', 50)
    spans = @tracer.writer.spans()
    assert_equal(spans.length, 2)
    span = spans[-1]
    assert_equal(span.name, 'rails.cache')
    assert_equal(span.span_type, 'cache')
    assert_equal(span.resource, 'SET')
    assert_equal(span.service, 'rails-cache')
    assert_equal(span.get_tag('rails.cache.backend').to_s, 'redis_store')
    assert_equal(span.get_tag('rails.cache.key'), 'custom-key')
    span = spans[-2]
    assert_equal(span.name, 'redis.command')
    assert_equal(span.span_type, 'redis')
    assert_match(/set custom-key .*ActiveSupport.*/, span.resource)
    assert_equal(span.service, 'redis')
    # the following ensures span will be correctly displayed (parent/child of the same trace)
    assert_equal(spans[-1].trace_id, spans[-2].trace_id)
    assert_equal(spans[-1].span_id, spans[-2].parent_id)
  end

  test 'cache.delete() is properly traced' do
    # use the cache and assert the proper span
    Rails.cache.delete('custom-key')
    spans = @tracer.writer.spans()
    assert_equal(spans.length, 2)
    span = spans[-1]
    assert_equal(span.name, 'rails.cache')
    assert_equal(span.span_type, 'cache')
    assert_equal(span.resource, 'DELETE')
    assert_equal(span.service, 'rails-cache')
    assert_equal(span.get_tag('rails.cache.backend').to_s, 'redis_store')
    assert_equal(span.get_tag('rails.cache.key'), 'custom-key')
    span = spans[-2]
    assert_equal(span.name, 'redis.command')
    assert_equal(span.span_type, 'redis')
    assert_equal(span.resource, 'del custom-key')
    assert_equal(span.service, 'redis')
    # the following ensures span will be correctly displayed (parent/child of the same trace)
    assert_equal(spans[-1].trace_id, spans[-2].trace_id)
    assert_equal(spans[-1].span_id, spans[-2].parent_id)
  end
end
