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

  test 'Sidekiq middleware uses Rails configuration if available' do
    @tracer.configure(enabled: false, debug: true, host: 'tracer.example.com', port: 7777)
    Datadog::Contrib::Rails::Framework.setup
    db_adapter = get_adapter_name

    # add Sidekiq middleware
    Sidekiq::Testing.server_middleware do |chain|
      chain.add(Datadog::Contrib::Sidekiq::ServerTracer, tracer: @tracer, service_name: 'rails-sidekiq')
    end

    # do something to force middleware execution
    EmptyWorker.perform_async
    assert_equal(
      @tracer.services,
      app_name => {
        'app' => 'rails', 'app_type' => 'web'
      },
      "#{app_name}-#{db_adapter}" => {
        'app' => 'active_record', 'app_type' => 'db'
      },
      "#{app_name}-cache" => {
        'app' => 'rails', 'app_type' => 'cache'
      },
      'rails-sidekiq' => {
        'app' => 'sidekiq', 'app_type' => 'worker'
      }
    )
  end
end
