require 'ddtrace/contrib/rails/rails_helper'

# It's important that there's *NO* "require 'redis-rails'" or
# even "require 'redis'" here. Because people using Rails do not
# include those headers themselves, instead they rely on the
# framework to do it for them. So it should work smoothly without
# including anything.
# raise 'Redis cannot be loaded for a realistic Rails test' if defined? Redis

# TODO better method names and RSpec contexts
RSpec.describe 'Rails application' do
  include_context 'Rails test application'
  include_context 'Tracer'

  before do
    host = ENV.fetch('TEST_REDIS_HOST', '127.0.0.1')
    port = ENV.fetch('TEST_REDIS_PORT', 6379)

    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("REDIS_URL").and_return("redis://#{host}:#{port}")
  end

  before { app }

  before do
    # switch Rails with a dummy tracer
    @original_tracer = Datadog.configuration[:rails][:tracer]
    Datadog.configuration[:rails][:tracer] = tracer
    Datadog.configuration.use(:redis)
    Datadog.configure(client_from_driver(driver), tracer: tracer)
  end

  after do
    Datadog.configuration[:rails][:tracer] = @original_tracer
  end

  let(:driver) do
    # For internal Redis store (Rails 5.2+), use the #redis method.
    # For redis-activesupport, get the Redis pin accessing private methods (only Rails 3.x)
    Rails.cache.respond_to?(:redis) ? Rails.cache.redis : Rails.cache.instance_variable_get(:@data)
  end

  let(:cache_store_name) do
    Gem.loaded_specs['redis-activesupport'] ? 'redis_store' : 'redis_cache_store'
  end

  it 'cache.read() and cache.fetch() are properly traced' do
    # read and fetch should behave exactly the same, and we shall
    # never see a read() having a fetch() as parent.
    [:read, :fetch].each do |f|
      # use the cache and assert the proper span
      Rails.cache.write('custom-key', 50)
      value = Rails.cache.send(f, 'custom-key')
      expect(value).to eq(50)

      expect(spans).to have(4).items
      cache, _, redis, = spans
      expect(cache.name).to eq('rails.cache')
      expect(cache.span_type).to eq('cache')
      expect(cache.resource).to eq('GET')
      expect(cache.service).to eq("#{app_name}-cache")
      expect(cache.get_tag('rails.cache.backend').to_s).to eq(cache_store_name)
      expect(cache.get_tag('rails.cache.key')).to eq('custom-key')

      expect(redis.name).to eq('redis.command')
      expect(redis.span_type).to eq('redis')
      expect(redis.resource).to eq('GET custom-key')
      expect(redis.get_tag('redis.raw_command')).to eq('GET custom-key')
      expect(redis.service).to eq('redis')
      # the following ensures span will be correctly displayed (parent/child of the same trace)
      expect(cache.trace_id).to eq(redis.trace_id)
      expect(cache.span_id).to eq(redis.parent_id)
    end
  end

  it 'cache.fetch() is properly traced and handles blocks' do
    Rails.cache.delete('custom-key')
    clear_spans # empty spans

    # value does not exist, fetch should both store it and return it
    value = Rails.cache.fetch('custom-key') do
      51
    end
    expect(value).to eq(51)

    expect(spans).to have(4).items

    cache_get, cache_set, redis_get, redis_set = spans

    expect(cache_set.name).to eq('rails.cache')
    expect(cache_set.resource).to eq('SET')
    expect(redis_set.name).to eq('redis.command')
    expect(cache_get.name).to eq('rails.cache')
    expect(cache_get.resource).to eq('GET')
    expect(redis_get.name).to eq('redis.command')

    # check that the value is really updated, and persistent
    value = Rails.cache.read('custom-key')
    clear_spans # empty spans
    expect(value).to eq(51)

    # if value exists, fetch returns it and does no update
    value = Rails.cache.fetch('custom-key') do
      52
    end
    expect(value).to eq(51)

    expect(spans).to have(2).items

    cache, redis = spans
    expect(cache.name).to eq('rails.cache')
    expect(redis.name).to eq('redis.command')
  end

  it 'cache.write() is properly traced' do
    # use the cache and assert the proper span
    Rails.cache.write('custom-key', 50)
    expect(spans).to have(2).items
    cache, redis = spans

    expect(cache.name).to eq('rails.cache')
    expect(cache.span_type).to eq('cache')
    expect(cache.resource).to eq('SET')
    expect(cache.service).to eq("#{app_name}-cache")
    expect(cache.get_tag('rails.cache.backend').to_s).to eq(cache_store_name)
    expect(cache.get_tag('rails.cache.key')).to eq('custom-key')

    expect(redis.name).to eq('redis.command')
    expect(redis.span_type).to eq('redis')
    expect(redis.resource).to match(/SET custom-key .*ActiveSupport.*/)
    expect(redis.get_tag('redis.raw_command')).to match(/SET custom-key .*ActiveSupport.*/)
    expect(redis.service).to eq('redis')
    # the following ensures span will be correctly displayed (parent/child of the same trace)
    expect(cache.trace_id).to eq(redis.trace_id)
    expect(cache.span_id).to eq(redis.parent_id)
  end

  it 'cache.delete() is properly traced' do
    # use the cache and assert the proper span
    Rails.cache.delete('custom-key')
    expect(spans).to have(2).items
    cache, del = spans

    expect(cache.name).to eq('rails.cache')
    expect(cache.span_type).to eq('cache')
    expect(cache.resource).to eq('DELETE')
    expect(cache.service).to eq("#{app_name}-cache")
    expect(cache.get_tag('rails.cache.backend').to_s).to eq(cache_store_name)
    expect(cache.get_tag('rails.cache.key')).to eq('custom-key')

    expect(del.name).to eq('redis.command')
    expect(del.span_type).to eq('redis')
    expect(del.resource).to eq('DEL custom-key')
    expect(del.get_tag('redis.raw_command')).to eq('DEL custom-key')
    expect(del.service).to eq('redis')
    # the following ensures span will be correctly displayed (parent/child of the same trace)
    expect(cache.trace_id).to eq(del.trace_id)
    expect(cache.span_id).to eq(del.parent_id)
  end

  it 'cache key is expanded using ActiveSupport' do
    class User
      def cache_key
        'User:3'
      end
    end

    Rails.cache.write(['custom-key', %w[x y], User.new], 50)
    expect(spans).to have(2).items
    cache, _redis = spans
    expect(cache.get_tag('rails.cache.key')).to eq('custom-key/x/y/User:3')
  end

  private

  def client_from_driver(driver)
    if Gem::Version.new(::Redis::VERSION) >= Gem::Version.new('4.0.0')
      driver._client
    else
      driver.client
    end
  end
end
