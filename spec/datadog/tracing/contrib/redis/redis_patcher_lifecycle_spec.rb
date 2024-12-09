require 'datadog/tracing/contrib/support/spec_helper'

require 'redis'
require 'datadog'

# This must be a standalone task due to the life cycle of patcher
RSpec.describe 'Patcher lifecycle - instrumenting a redis instance initialized before patching instrumentation' do
  let(:host) { ENV.fetch('TEST_REDIS_HOST', '127.0.0.1') }
  let(:port) { ENV.fetch('TEST_REDIS_PORT', 6379).to_i }

  def redis_options(service_name = nil)
    options = { host: host, port: port }
    return options if service_name.nil?

    options.merge(
      custom: { datadog: { service_name: service_name } }
    )
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:redis].reset_configuration!
    example.run
    Datadog.registry[:redis].reset_configuration!
  end

  # NOTE: on Redis < 5, we'd instrument a redis instance using Datadog.configure_onto(...),
  #  as of Redis >=5 however, there's a supported middleware API that we make use of, so
  #  instead one can instrument a redis instance by initiating it with:
  #  `Redis.new(..., custom: { datadog: { ... } } )`
  context(
    'when instrumenting using `configure_onto` to hold instrumentation configuration',
    skip: Gem::Version.new(Redis::VERSION) >= Gem::Version.new('5') ? 'Not supported' : false
  ) do
    it do
      # This redis instance was initialized before Datadog redis instrumentation was configured.
      redis_1 = Redis.new(redis_options)

      Datadog.configure do |c|
        c.tracing.instrument :redis, service_name: 'my-redis'
      end

      redis_2 = Redis.new(redis_options)

      redis_3 = Redis.new(redis_options)

      Datadog.configure_onto(redis_1, service_name: 'my-custom-redis')

      # This configure_onto works fine, as it was initialized after Datadog redis
      # instrumentation was configured.
      Datadog.configure_onto(redis_2, service_name: 'my-other-redis')

      redis_1.ping
      redis_2.ping
      redis_3.ping

      span_1, span_2, span_3 = spans

      expect(span_1.service).to eq('my-custom-redis')
      expect(span_2.service).to eq('my-other-redis')
      expect(span_3.service).to eq('my-redis')
    end
  end

  context(
    'when instrumenting using `custom` attribute to hold instrumentation configuration',
    skip: Gem::Version.new(Redis::VERSION) < Gem::Version.new('5') ? 'Not supported' : false
  ) do
    it do
      redis_1 = Redis.new(redis_options('my-custom-redis'))

      Datadog.configure do |c|
        c.tracing.instrument :redis, service_name: 'my-redis'
      end

      redis_2 = Redis.new(redis_options('my-other-redis'))
      redis_3 = Redis.new(redis_options)

      redis_1.ping
      redis_2.ping
      redis_3.ping

      span_1, span_2, span_3 = spans

      expect(span_1.service).to eq('my-custom-redis')
      expect(span_2.service).to eq('my-other-redis')
      expect(span_3.service).to eq('my-redis')
    end
  end

  context(
    'when instrumenting using `custom` with `RedisClient`',
    skip: Gem::Version.new(Redis::VERSION) < Gem::Version.new('5') ? 'Not supported' : false
  ) do
    it do
      redis_1 = RedisClient.config(**redis_options('my-custom-redis')).new_client

      Datadog.configure do |c|
        c.tracing.instrument :redis, service_name: 'my-redis'
      end

      redis_2 = RedisClient.config(**redis_options('my-other-redis')).new_client
      redis_3 = RedisClient.config(**redis_options).new_client

      redis_1.call('PING')
      redis_2.call('PING')
      redis_3.call('PING')

      span_1, span_2, span_3 = spans

      expect(span_1.service).to eq('my-custom-redis')
      expect(span_2.service).to eq('my-other-redis')
      expect(span_3.service).to eq('my-redis')
    end
  end
end
