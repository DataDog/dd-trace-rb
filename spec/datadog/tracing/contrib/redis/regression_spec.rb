require 'datadog/tracing/contrib/support/spec_helper'

require 'redis'
require 'ddtrace'

# The regression task must be a standalone task due to the life cycle of patcher
RSpec.describe 'Regression', skip: Gem::Version.new(Redis::VERSION) >= Gem::Version.new('5') ? 'Not supported' : false do
  let(:host) { ENV.fetch('TEST_REDIS_HOST', '127.0.0.1') }
  let(:port) { ENV.fetch('TEST_REDIS_PORT', 6379).to_i }
  let(:default_redis_options) { { host: host, port: port } }

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:redis].reset_configuration!
    example.run
    Datadog.registry[:redis].reset_configuration!
  end

  context 'when given redis instance initialized before patching instrumentation' do
    it do
      # This redis instance was initialized before Datadog redis instrumentation was configured.
      redis_1 = Redis.new(default_redis_options)

      Datadog.configure do |c|
        c.tracing.instrument :redis, service_name: 'my-redis'
      end

      redis_2 = Redis.new(default_redis_options)

      redis_3 = Redis.new(default_redis_options)

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
end
