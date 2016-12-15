ENV['DATADOG_TRACE_AUTOPATCH'] = 'true'
ENV['DATADOG_TEST_REDIS_CACHE_HOST'] = '127.0.0.1'
ENV['DATADOG_TEST_REDIS_CACHE_PORT'] = '46379'

require 'redis-store'

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
    Rails.cache.read('custom-key')

    spans = @tracer.writer.spans()
    assert_operator(spans.length, :>=, 1)
    span = spans[-1]
    assert_equal(span.name, 'rails.cache')
    assert_equal(span.span_type, 'cache')
    assert_equal(span.resource, 'GET')
    assert_equal(span.service, 'rails-cache')
    assert_equal(span.get_tag('rails.cache.backend').to_s, '[:redis_store, {:host=>"127.0.0.1", :port=>"46379"}]')
    assert_equal(span.get_tag('rails.cache.key'), 'custom-key')
  end
end
