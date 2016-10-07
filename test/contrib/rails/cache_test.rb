require 'helper'
require 'contrib/rails/test_helper'

class CacheTracingTest < ActionController::TestCase
  test 'cache.read() is properly traced' do
    # use a dummy tracer
    tracer = get_test_tracer
    Rails.configuration.datadog_trace[:tracer] = tracer

    # use the cache and assert the proper span
    Rails.cache.read('custom-key')
    spans = tracer.writer.spans()
    assert_equal(spans.length, 1)
    span = spans[0]
    assert_equal(span.name, 'rails.cache')
    assert_equal(span.span_type, 'cache')
    assert_equal(span.resource, 'GET')
    assert_equal(span.get_tag('rails.cache.backend').to_s, 'memory_store')
    assert_equal(span.get_tag('rails.cache.key'), 'custom-key')
    assert span.to_hash[:duration] > 0
  end

  test 'cache.write() is properly traced' do
    # use a dummy tracer
    tracer = get_test_tracer
    Rails.configuration.datadog_trace[:tracer] = tracer

    # use the cache and assert the proper span
    Rails.cache.write('custom-key', 50)
    spans = tracer.writer.spans()
    assert_equal(spans.length, 1)
    span = spans[0]
    assert_equal(span.name, 'rails.cache')
    assert_equal(span.span_type, 'cache')
    assert_equal(span.resource, 'SET')
    assert_equal(span.get_tag('rails.cache.backend').to_s, 'memory_store')
    assert_equal(span.get_tag('rails.cache.key'), 'custom-key')
    assert span.to_hash[:duration] > 0
  end

  test 'cache.delete() is properly traced' do
    # use a dummy tracer
    tracer = get_test_tracer
    Rails.configuration.datadog_trace[:tracer] = tracer

    # use the cache and assert the proper span
    Rails.cache.delete('custom-key')
    spans = tracer.writer.spans()
    assert_equal(spans.length, 1)
    span = spans[0]
    assert_equal(span.name, 'rails.cache')
    assert_equal(span.span_type, 'cache')
    assert_equal(span.resource, 'DELETE')
    assert_equal(span.get_tag('rails.cache.backend').to_s, 'memory_store')
    assert_equal(span.get_tag('rails.cache.key'), 'custom-key')
    assert span.to_hash[:duration] > 0
  end
end
