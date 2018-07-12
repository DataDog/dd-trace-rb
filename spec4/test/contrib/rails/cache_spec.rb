require('helper')
require('contrib/rails/test_helper')
require('securerandom')
require('ddtrace/ext/cache')
RSpec.describe(CacheTracing) do
  before do
    @original_tracer = Datadog.configuration[:rails][:tracer]
    @tracer = get_test_tracer
    Datadog.configuration[:rails][:cache_service] = 'rails-cache'
    Datadog.configuration[:rails][:tracer] = @tracer
  end
  after { Datadog.configuration[:rails][:tracer] = @original_tracer }
  it('cache.read() is properly traced') do
    Rails.cache.write('custom-key', 50)
    value = Rails.cache.read('custom-key')
    expect(value).to(eq(50))
    spans = @tracer.writer.spans
    expect(2).to(eq(spans.length))
    get, set = spans
    expect('rails.cache').to(eq(get.name))
    expect('cache').to(eq(get.span_type))
    expect('GET').to(eq(get.resource))
    expect('rails-cache').to(eq(get.service))
    expect('file_store').to(eq(get.get_tag('rails.cache.backend').to_s))
    expect('custom-key').to(eq(get.get_tag('rails.cache.key')))
    expect('rails.cache').to(eq(set.name))
  end
  it('cache.write() is properly traced') do
    Rails.cache.write('custom-key', 50)
    spans = @tracer.writer.spans
    expect(1).to(eq(spans.length))
    span = spans[0]
    expect('rails.cache').to(eq(span.name))
    expect('cache').to(eq(span.span_type))
    expect('SET').to(eq(span.resource))
    expect('rails-cache').to(eq(span.service))
    expect('file_store').to(eq(span.get_tag('rails.cache.backend').to_s))
    expect('custom-key').to(eq(span.get_tag('rails.cache.key')))
  end
  it('cache.delete() is properly traced') do
    Rails.cache.delete('custom-key')
    spans = @tracer.writer.spans
    expect(1).to(eq(spans.length))
    span = spans[0]
    expect('rails.cache').to(eq(span.name))
    expect('cache').to(eq(span.span_type))
    expect('DELETE').to(eq(span.resource))
    expect('rails-cache').to(eq(span.service))
    expect('file_store').to(eq(span.get_tag('rails.cache.backend').to_s))
    expect('custom-key').to(eq(span.get_tag('rails.cache.key')))
  end
  it('cache exception handling') do
    expect { Rails.cache.fetch('exception') { (1 / 0) } }.to(raise_error)
    spans = @tracer.writer.spans
    expect(1).to(eq(spans.length))
    span = spans[0]
    expect('rails.cache').to(eq(span.name))
    expect('cache').to(eq(span.span_type))
    expect('GET').to(eq(span.resource))
    expect('rails-cache').to(eq(span.service))
    expect('file_store').to(eq(span.get_tag('rails.cache.backend').to_s))
    expect('exception').to(eq(span.get_tag('rails.cache.key')))
    expect('ZeroDivisionError').to(eq(span.get_tag('error.type')))
    expect('divided by 0').to(eq(span.get_tag('error.msg')))
  end
  it('doing a cache call uses the proper service name if it is changed') do
    update_config(:cache_service, 'service-cache')
    Rails.cache.write('custom-key', 50)
    spans = @tracer.writer.spans
    expect(1).to(eq(spans.length))
    span = spans.first
    expect('service-cache').to(eq(span.service))
    reset_config
  end
  it('cache key truncation regression') do
    max_key_size = Datadog::Ext::CACHE::MAX_KEY_SIZE
    large_key = ''.ljust((max_key_size * 2), SecureRandom.hex)
    Rails.cache.write(large_key, 'foobar')
    spans = @tracer.writer.spans
    expect(spans.length).to(eq(1))
    span = spans[0]
    expect((large_key.size > max_key_size)).to(be_truthy)
    expect('rails.cache').to(eq(span.name))
    expect(span.get_tag('rails.cache.key').length).to(eq(max_key_size))
    expect(span.get_tag('rails.cache.key').end_with?('...')).to(eq(true))
  end
end
