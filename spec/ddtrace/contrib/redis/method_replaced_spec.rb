require 'spec_helper'

require 'redis'
require 'hiredis'
require 'ddtrace'

RSpec.describe 'Redis replace method test' do
  before(:each) do
    skip unless ENV['TEST_DATADOG_INTEGRATION']

    Datadog.configure do |c|
      c.use :redis
    end
  end

  let(:redis) { Redis.new(host: host, port: port) }
  let(:host) { ENV.fetch('TEST_REDIS_HOST', '127.0.0.1') }
  let(:port) { ENV.fetch('TEST_REDIS_PORT', 6379).to_i }

  let(:call_without_datadog_method) do
    Redis::Client.instance_methods.find { |m| m == :call_without_datadog }
  end

  it do
    expect(call_without_datadog_method).to_not be nil
    expect(redis).to receive(:call).once.and_call_original
    redis.call('ping', 'hello world')
  end
end
