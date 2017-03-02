
require 'sidekiq/testing'
require 'ddtrace'
require 'ddtrace/contrib/sidekiq/tracer'
require 'helper'

class TracerTestBase < Minitest::Test
  REDIS_HOST = '127.0.0.1'.freeze()
  REDIS_PORT = 46379

  def setup
    @writer = FauxWriter.new()
    @tracer = Datadog::Tracer.new(writer: @writer)

    redis_url = "redis://#{REDIS_HOST}:#{REDIS_PORT}"

    Sidekiq.configure_client do |config|
      config.redis = { url: redis_url }
    end

    Sidekiq.configure_server do |config|
      config.redis = { url: redis_url }
    end

    Sidekiq::Testing.inline!
  end
end
