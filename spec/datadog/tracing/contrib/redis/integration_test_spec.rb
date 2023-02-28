require 'datadog/tracing/contrib/support/spec_helper'

require 'time'
require 'redis'
require 'ddtrace'

RSpec.describe 'Redis integration test' do
  before do
    skip unless ENV['TEST_DATADOG_INTEGRATION']

    use_real_tracer!

    Datadog.configure do |c|
      c.tracing.instrument :redis
    end
  end

  after do
    Datadog.registry[:redis].reset_configuration!
    without_warnings { Datadog.configuration.reset! }
  end
  let(:redis_options) { { host: host, port: port } }
  let(:redis) { Redis.new(redis_options.freeze) }
  let(:host) { ENV.fetch('TEST_REDIS_HOST', '127.0.0.1') }
  let(:port) { ENV.fetch('TEST_REDIS_PORT', 6379).to_i }

  it do
    expect(redis.set('FOO', 'bar')).to eq('OK')
    expect(redis.get('FOO')).to eq('bar')
    try_wait_until(seconds: 3) { tracer.writer.stats[:traces_flushed] >= 2 }
    expect(tracer.writer.stats[:traces_flushed]).to be >= 2
  end
end
