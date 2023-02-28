require 'datadog/tracing/contrib/integration_examples'
require 'datadog/tracing/contrib/rails/rails_helper'

# It's important that there's *NO* "require 'redis-rails'" or
# even "require 'redis'" here. Because people using Rails do not
# include those headers themselves, instead they rely on the
# framework to do it for them. So it should work smoothly without
# including anything.
# raise 'Redis cannot be loaded for a realistic Rails test' if defined? Redis
RSpec.describe 'Rails Redis cache' do
  before(:all) do
    expect(Datadog::Tracing::Contrib::ActiveSupport::Cache::Patcher.patched?).to(
      be_falsey, <<MESSAGE)
      ActiveSupport::Cache has already been patched.
      This suite tests the behaviour of dd-trace-rb when patching with Redis enabled.
      Please run this suite before ActiveSupport::Cache is patched.
MESSAGE
  end

  include_context 'Rails test application'

  before do
    host = ENV.fetch('TEST_REDIS_HOST', '127.0.0.1')
    port = ENV.fetch('TEST_REDIS_PORT', 6379)

    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('REDIS_URL').and_return("redis://#{host}:#{port}")

    if ENV['EXPECT_RAILS_ACTIVESUPPORT'] == 'true'
      require 'redis-activesupport'

      expect(cache_store_name).to(
        eq('redis_store'),
        'Tests are running with ENV["EXPECT_RAILS_ACTIVESUPPORT"] = true but the test application is not using ' \
        'the rails-activesupport gem.'
      )
    else
      expect(cache_store_name).to(
        eq('redis_cache_store'),
        'Tests are running without ENV["EXPECT_RAILS_ACTIVESUPPORT"] being set but the test application is not using ' \
        'the rails built-in redis support.'
      )
    end
  end

  before { app }

  before do
    Datadog.configure { |c| c.tracing.instrument :redis }
    Datadog.configure_onto(client_from_driver(driver))
  end

  let(:driver) do
    # For internal Redis store (Rails 5.2+), use the #redis method.
    # For redis-activesupport, get the Redis pin accessing private methods (only Rails 3.x)
    Rails.cache.respond_to?(:redis) ? Rails.cache.redis : Rails.cache.instance_variable_get(:@data)
  end
  let(:key) { 'custom-key' }

  let(:cache_store_name) do
    if Gem.loaded_specs['redis-activesupport']
      'redis_store'
    else
      'redis_cache_store'
    end
  end

  let(:cache) { Rails.cache }

  after { cache && cache.clear }

  shared_examples 'reader method' do |method|
    subject(:read) { cache.public_send(method, key) }

    before { cache.write(key, 50) }

    it do
      expect(read).to eq(50)

      expect(spans).to have(4).items
      cache, _, redis, = spans
      expect(cache.get_tag('rails.cache.backend')).to eq(cache_store_name)

      expect(redis.name).to eq('redis.command')
      expect(redis.span_type).to eq('redis')
      expect(redis.resource).to eq('GET custom-key')
      expect(redis.get_tag('redis.raw_command')).to eq('GET custom-key')
      expect(redis.service).to eq('redis')
      # the following ensures span will be correctly displayed (parent/child of the same trace)
      expect(cache.trace_id).to eq(redis.trace_id)
      expect(cache.span_id).to eq(redis.parent_id)

      expect(cache.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
        .to eq('active_support')
      expect(cache.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
        .to eq('cache')
      expect(cache.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE))
        .to eq('active_support-cache')
    end

    it_behaves_like 'a peer service span' do
      let(:span) { spans.last }
    end
  end

  describe '#read' do
    it_behaves_like 'reader method', :read
  end

  describe '#fetch' do
    it_behaves_like 'reader method', :fetch

    context 'with block' do
      subject(:fetch) { cache.fetch(key) { 51 } }

      it 'retrieves and stores default value' do
        expect(fetch).to eq(51)

        expect(spans).to have(4).items

        cache_get, cache_set, redis_get, redis_set = spans

        expect(cache_set.name).to eq('rails.cache')
        expect(cache_set.resource).to eq('SET')
        expect(redis_set.name).to eq('redis.command')
        expect(cache_get.name).to eq('rails.cache')
        expect(cache_get.resource).to eq('GET')
        expect(redis_get.name).to eq('redis.command')

        expect(cache_get.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
          .to eq('active_support')
        expect(cache_get.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
          .to eq('cache')
        expect(cache_get.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE))
          .to eq('active_support-cache')

        expect(cache_set.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
          .to eq('active_support')
        expect(cache_set.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
          .to eq('cache')
        expect(cache_set.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE))
          .to eq('active_support-cache')

        # check that the value is really updated, and persistent
        expect(cache.read(key)).to eq(51)
        clear_traces!

        # if value exists, fetch returns it and does no update
        expect(cache.fetch(key) { 7 }).to eq(51)

        expect(spans).to have(2).items

        cache, redis = spans
        expect(cache.name).to eq('rails.cache')
        expect(redis.name).to eq('redis.command')

        expect(cache.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
          .to eq('active_support')
        expect(cache.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
          .to eq('cache')
        expect(cache.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE))
          .to eq('active_support-cache')
      end
    end
  end

  describe '#write' do
    subject!(:write) { cache.write(key, 50) }

    it do
      expect(spans).to have(2).items
      cache, redis = spans

      expect(cache.get_tag('rails.cache.backend')).to eq(cache_store_name)

      expect(redis.name).to eq('redis.command')
      expect(redis.span_type).to eq('redis')
      expect(redis.resource).to match(/SET custom-key .*ActiveSupport.*/)
      expect(redis.get_tag('redis.raw_command')).to match(/SET custom-key .*ActiveSupport.*/)
      expect(redis.service).to eq('redis')
      # the following ensures span will be correctly displayed (parent/child of the same trace)
      expect(cache.trace_id).to eq(redis.trace_id)
      expect(cache.span_id).to eq(redis.parent_id)

      expect(cache.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
        .to eq('active_support')
      expect(cache.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
        .to eq('cache')
      expect(cache.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE))
        .to eq('active_support-cache')
    end

    it_behaves_like 'a peer service span' do
      let(:span) { spans.last }
    end
  end

  describe '#delete' do
    subject!(:write) { cache.delete(key) }

    it do
      expect(spans).to have(2).items
      cache, del = spans

      expect(cache.get_tag('rails.cache.backend')).to eq(cache_store_name)

      expect(del.name).to eq('redis.command')
      expect(del.span_type).to eq('redis')
      expect(del.resource).to eq('DEL custom-key')
      expect(del.get_tag('redis.raw_command')).to eq('DEL custom-key')
      expect(del.service).to eq('redis')
      # the following ensures span will be correctly displayed (parent/child of the same trace)
      expect(cache.trace_id).to eq(del.trace_id)
      expect(cache.span_id).to eq(del.parent_id)

      expect(cache.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
        .to eq('active_support')
      expect(cache.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
        .to eq('cache')
      expect(cache.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE))
        .to eq('active_support-cache')
    end

    it_behaves_like 'a peer service span' do
      let(:span) { spans.last }
    end
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
