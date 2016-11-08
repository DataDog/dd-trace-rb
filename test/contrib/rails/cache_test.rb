require 'helper'
require 'contrib/rails/test_helper'

class CacheTracingTest < ActionController::TestCase
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
    assert_equal(span.get_tag('rails.cache.backend').to_s, '[:file_store, "/tmp/ddtrace-rb/cache/"]')
    assert_equal(span.get_tag('rails.cache.key'), 'custom-key')
    assert span.to_hash[:duration] > 0
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
    assert_equal(span.get_tag('rails.cache.backend').to_s, '[:file_store, "/tmp/ddtrace-rb/cache/"]')
    assert_equal(span.get_tag('rails.cache.key'), 'custom-key')
    assert span.to_hash[:duration] > 0
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
    assert_equal(span.get_tag('rails.cache.backend').to_s, '[:file_store, "/tmp/ddtrace-rb/cache/"]')
    assert_equal(span.get_tag('rails.cache.key'), 'custom-key')
    assert span.to_hash[:duration] > 0
  end
end
