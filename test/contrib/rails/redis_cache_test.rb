ENV['DATADOG_TRACE_AUTOPATCH'] = 'true'
ENV['DATADOG_TEST_REDIS_CACHE_HOST'] = '127.0.0.1'
ENV['DATADOG_TEST_REDIS_CACHE_PORT'] = '46379'

require 'redis-activesupport'
require 'helper'
require 'contrib/rails/test_helper'

class RedisCacheTracingTest < ActionController::TestCase
  setup do
    @original_tracer = Rails.configuration.datadog_trace[:tracer]
    @tracer = get_test_tracer
    Rails.configuration.datadog_trace[:tracer] = @tracer
  end

  teardown do
    Rails.configuration.datadog_trace[:tracer] = @original_tracer
  end

  test 'cache.read() is properly traced' do
    # use the cache and assert the proper span
    Rails.cache.write('custom-key', 50)
    value = Rails.cache.read('custom-key')
    assert_equal(50, value)

    spans = @tracer.writer.spans()
    assert_equal(spans.length, 2)
    span = spans[-1]
    assert_equal(span.name, 'rails.cache')
    assert_equal(span.span_type, 'cache')
    assert_equal(span.resource, 'GET')
    assert_equal(span.service, 'rails-cache')
    assert_equal(span.get_tag('rails.cache.backend').to_s, '[:redis_store, {:host=>"127.0.0.1", :port=>"46379"}]')
    assert_equal(span.get_tag('rails.cache.key'), 'custom-key')
  end

  test 'cache.write() is properly traced' do
    # use the cache and assert the proper span
    Rails.cache.write('custom-key', 50)
    spans = @tracer.writer.spans()
    assert_equal(spans.length, 1)
    span = spans[0]
    assert_equal(span.name, 'rails.cache')
    assert_equal(span.span_type, 'cache')
    assert_equal(span.resource, 'SET')
    assert_equal(span.service, 'rails-cache')
    assert_equal(span.get_tag('rails.cache.backend').to_s, '[:redis_store, {:host=>"127.0.0.1", :port=>"46379"}]')
    assert_equal(span.get_tag('rails.cache.key'), 'custom-key')
  end

  test 'cache.delete() is properly traced' do
    # use the cache and assert the proper span
    Rails.cache.delete('custom-key')
    spans = @tracer.writer.spans()
    assert_equal(spans.length, 1)
    span = spans[0]
    assert_equal(span.name, 'rails.cache')
    assert_equal(span.span_type, 'cache')
    assert_equal(span.resource, 'DELETE')
    assert_equal(span.service, 'rails-cache')
    assert_equal(span.get_tag('rails.cache.backend').to_s, '[:redis_store, {:host=>"127.0.0.1", :port=>"46379"}]')
    assert_equal(span.get_tag('rails.cache.key'), 'custom-key')
  end

  test 'doing a cache call uses the proper service name if it is changed' do
    # update database configuration
    update_config(:default_cache_service, 'service-cache')

    # make the cache write and assert the proper spans
    Rails.cache.write('custom-key', 50)
    spans = @tracer.writer.spans()
    assert_equal(spans.length, 1)
    span = spans.first
    assert_equal(span.service, 'service-cache')

    # reset the original configuration
    reset_config()
  end
end
