host = ENV.fetch('TEST_REDIS_HOST', '127.0.0.1')
port = ENV.fetch('TEST_REDIS_PORT', 6379)
ENV['REDIS_URL'] = "redis://#{host}:#{port}"
require('helper')
require('contrib/rails/test_helper')
RSpec.describe(RedisCacheTracing) do
  before do
    @original_tracer = Datadog.configuration[:rails][:tracer]
    @tracer = get_test_tracer
    Datadog.configuration[:rails][:tracer] = @tracer
    Datadog.configuration.use(:redis)
    driver = Rails.cache.instance_variable_get(:@data)
    Datadog.configure(client_from_driver(driver), tracer: @tracer)
  end
  after { Datadog.configuration[:rails][:tracer] = @original_tracer }
  it('cache.read() and cache.fetch() are properly traced') do
    [:read, :fetch].each do |f|
      Rails.cache.write('custom-key', 50)
      value = Rails.cache.send(f, 'custom-key')
      expect(value).to(eq(50))
      spans = @tracer.writer.spans
      expect(4).to(eq(spans.length))
      cache, _, redis = spans
      expect('rails.cache').to(eq(cache.name))
      expect('cache').to(eq(cache.span_type))
      expect('GET').to(eq(cache.resource))
      expect("#{app_name}-cache").to(eq(cache.service))
      expect('redis_store').to(eq(cache.get_tag('rails.cache.backend').to_s))
      expect('custom-key').to(eq(cache.get_tag('rails.cache.key')))
      expect('redis.command').to(eq(redis.name))
      expect('redis').to(eq(redis.span_type))
      expect('GET custom-key').to(eq(redis.resource))
      expect('GET custom-key').to(eq(redis.get_tag('redis.raw_command')))
      expect('redis').to(eq(redis.service))
      expect(redis.trace_id).to(eq(cache.trace_id))
      expect(redis.parent_id).to(eq(cache.span_id))
    end
  end
  it('cache.fetch() is properly traced and handles blocks') do
    Rails.cache.delete('custom-key')
    @tracer.writer.spans
    value = Rails.cache.fetch('custom-key') { 51 }
    expect(value).to(eq(51))
    spans = @tracer.writer.spans
    expect(spans.length).to(eq(4))
    cache_get, cache_set, redis_get, redis_set = spans
    expect('rails.cache').to(eq(cache_set.name))
    expect('SET').to(eq(cache_set.resource))
    expect('redis.command').to(eq(redis_set.name))
    expect('rails.cache').to(eq(cache_get.name))
    expect('GET').to(eq(cache_get.resource))
    expect('redis.command').to(eq(redis_get.name))
    value = Rails.cache.read('custom-key')
    @tracer.writer.spans
    expect(51).to(eq(value))
    value = Rails.cache.fetch('custom-key') { 52 }
    expect(value).to(eq(51))
    spans = @tracer.writer.spans
    expect(spans.length).to(eq(2))
    cache, redis = spans
    expect('rails.cache').to(eq(cache.name))
    expect('redis.command').to(eq(redis.name))
  end
  it('cache.write() is properly traced') do
    Rails.cache.write('custom-key', 50)
    spans = @tracer.writer.spans
    expect(2).to(eq(spans.length))
    cache, redis = spans
    expect('rails.cache').to(eq(cache.name))
    expect('cache').to(eq(cache.span_type))
    expect('SET').to(eq(cache.resource))
    expect("#{app_name}-cache").to(eq(cache.service))
    expect('redis_store').to(eq(cache.get_tag('rails.cache.backend').to_s))
    expect('custom-key').to(eq(cache.get_tag('rails.cache.key')))
    expect('redis.command').to(eq(redis.name))
    expect('redis').to(eq(redis.span_type))
    expect(redis.resource).to(match(/SET custom-key .*ActiveSupport.*/))
    expect(redis.get_tag('redis.raw_command')).to(match(/SET custom-key .*ActiveSupport.*/))
    expect('redis').to(eq(redis.service))
    expect(redis.trace_id).to(eq(cache.trace_id))
    expect(redis.parent_id).to(eq(cache.span_id))
  end
  it('cache.delete() is properly traced') do
    Rails.cache.delete('custom-key')
    spans = @tracer.writer.spans
    expect(2).to(eq(spans.length))
    cache, del = spans
    expect('rails.cache').to(eq(cache.name))
    expect('cache').to(eq(cache.span_type))
    expect('DELETE').to(eq(cache.resource))
    expect("#{app_name}-cache").to(eq(cache.service))
    expect('redis_store').to(eq(cache.get_tag('rails.cache.backend').to_s))
    expect('custom-key').to(eq(cache.get_tag('rails.cache.key')))
    expect('redis.command').to(eq(del.name))
    expect('redis').to(eq(del.span_type))
    expect('DEL custom-key').to(eq(del.resource))
    expect('DEL custom-key').to(eq(del.get_tag('redis.raw_command')))
    expect('redis').to(eq(del.service))
    expect(del.trace_id).to(eq(cache.trace_id))
    expect(del.parent_id).to(eq(cache.span_id))
  end

  private

  # switch Rails with a dummy tracer
  # get the Redis pin accessing private methods (only Rails 3.x)
  # read and fetch should behave exactly the same, and we shall
  # never see a read() having a fetch() as parent.
  # use the cache and assert the proper span
  # the following ensures span will be correctly displayed (parent/child of the same trace)
  # empty spans
  # value does not exist, fetch should both store it and return it
  # check that the value is really updated, and persistent
  # empty spans
  # if value exists, fetch returns it and does no update
  # use the cache and assert the proper span
  # the following ensures span will be correctly displayed (parent/child of the same trace)
  # use the cache and assert the proper span
  # the following ensures span will be correctly displayed (parent/child of the same trace)
  def client_from_driver(driver)
    if Gem::Version.new(::Redis::VERSION) >= Gem::Version.new('4.0.0')
      driver._client
    else
      driver.client
    end
  end
end
