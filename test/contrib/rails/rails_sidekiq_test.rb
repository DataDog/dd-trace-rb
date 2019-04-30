# This module tests the right integration between Sidekiq and
# Rails. Functionality tests for Rails and Sidekiq must go
# in their testing modules.
require 'helper'
require 'sidekiq/testing'
require 'contrib/rails/test_helper'
require 'ddtrace/contrib/sidekiq/server_tracer'

class RailsSidekiqTest < ActionController::TestCase
  setup do
    # don't pollute the global tracer
    @original_tracer = Datadog.configuration[:rails][:tracer]
    @tracer = get_test_tracer
    Datadog.configuration[:rails][:tracer] = @tracer

    # configure Sidekiq
    Sidekiq.configure_client do |config|
      config.redis = { url: ENV['REDIS_URL'] }
    end

    Sidekiq.configure_server do |config|
      config.redis = { url: ENV['REDIS_URL'] }
    end

    Sidekiq::Testing.inline!
  end

  teardown do
    Datadog.configuration[:rails][:tracer] = @original_tracer
  end

  # Sidekiq test job
  class EmptyWorker
    include Sidekiq::Worker

    def perform; end
  end
end
