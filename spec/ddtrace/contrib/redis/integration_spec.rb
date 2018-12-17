require 'spec_helper'

require 'time'
require 'redis'
require 'hiredis'
require 'ddtrace'

RSpec.describe 'Redis integration test' do
  # Use real tracer
  let(:tracer) do
    Datadog::Tracer.new
  end

  before(:each) do
    skip unless ENV['TEST_DATADOG_INTEGRATION']

    # Make sure to reset default tracer
    Datadog.configure do |c|
      c.use :redis, tracer: tracer
    end
  end

  after(:each) do
    Datadog.configure do |c|
      c.use :redis
    end
  end

  let(:redis) { Redis.new(host: host, port: port) }
  let(:host) { ENV.fetch('TEST_REDIS_HOST', '127.0.0.1') }
  let(:port) { ENV.fetch('TEST_REDIS_PORT', 6379).to_i }

  it do
    expect(redis.set('FOO', 'bar')).to eq('OK')
    expect(redis.get('FOO')).to eq('bar')
    try_wait_until(attempts: 30) { tracer.writer.stats[:traces_flushed] >= 2 }
    expect(tracer.writer.stats[:traces_flushed]).to be >= 2
  end
end
