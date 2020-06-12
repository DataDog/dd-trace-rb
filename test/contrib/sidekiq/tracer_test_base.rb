
require 'sidekiq/testing'
require 'ddtrace'
require 'ddtrace/contrib/sidekiq/client_tracer'
require 'ddtrace/contrib/sidekiq/server_tracer'
require 'helper'

class TracerTestBase < Minitest::Test
  include TestTracerHelper

  REDIS_HOST = ENV.fetch('TEST_REDIS_HOST', '127.0.0.1').freeze
  REDIS_PORT = ENV.fetch('TEST_REDIS_PORT', 6379)

  def configure
    Datadog.configure do |c|
      c.use :sidekiq
    end

    redis_url = "redis://#{REDIS_HOST}:#{REDIS_PORT}"

    Sidekiq.configure_client do |config|
      config.redis = { url: redis_url }
    end

    Sidekiq.configure_server do |config|
      config.redis = { url: redis_url }
    end

    Sidekiq::Testing.inline!
  end

  def writer
    @tracer.writer
  end
end
