require 'helper'
require 'contrib/rails/test_helper'

class CacheTracingTest < ActionController::TestCase
  setup do
    @original_tracer = Datadog.configuration[:rails][:tracer]
    @tracer = get_test_tracer
    Datadog.configuration[:rails][:cache_service] = 'rails-cache'
    Datadog.configuration[:rails][:tracer] = @tracer
  end

  teardown do
    Datadog.configuration[:rails][:tracer] = @original_tracer
  end

  test 'cache.read() is properly traced' do
    # use the cache and assert the proper span
    Rails.cache.write('custom-key', 50)
    value = Rails.cache.read('custom-key')
    assert_equal(50, value)

    spans = @tracer.writer.spans()
    assert_equal(spans.length, 2)
    get, set = spans
    assert_equal(get.name, 'rails.cache')
    assert_equal(get.span_type, 'cache')
    assert_equal(get.resource, 'GET')
    assert_equal(get.service, 'rails-cache')
    assert_equal(get.get_tag('rails.cache.backend').to_s, 'file_store')
    assert_equal(get.get_tag('rails.cache.key'), 'custom-key')
    assert_equal(set.name, 'rails.cache')
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
    assert_equal(span.get_tag('rails.cache.backend').to_s, 'file_store')
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
    assert_equal(span.get_tag('rails.cache.backend').to_s, 'file_store')
    assert_equal(span.get_tag('rails.cache.key'), 'custom-key')
  end

  test 'cache exception handling' do
    # use the cache and assert the proper span
    assert_raise do
      Rails.cache.fetch('exception') do
        1 / 0
      end
    end
    spans = @tracer.writer.spans()
    assert_equal(spans.length, 1)
    span = spans[0]
    assert_equal(span.name, 'rails.cache')
    assert_equal(span.span_type, 'cache')
    assert_equal(span.resource, 'GET')
    assert_equal(span.service, 'rails-cache')
    assert_equal(span.get_tag('rails.cache.backend').to_s, 'file_store')
    assert_equal(span.get_tag('rails.cache.key'), 'exception')
    assert_equal(span.get_tag('error.type'), 'ZeroDivisionError')
    assert_equal(span.get_tag('error.msg'), 'divided by 0')
  end

  test 'doing a cache call uses the proper service name if it is changed' do
    # update database configuration
    update_config(:cache_service, 'service-cache')

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
