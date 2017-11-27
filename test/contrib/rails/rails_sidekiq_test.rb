# This module tests the right integration between Sidekiq and
# Rails. Functionality tests for Rails and Sidekiq must go
# in their testing modules.
require 'helper'
require 'sidekiq/testing'
require 'contrib/rails/test_helper'
require 'ddtrace/contrib/sidekiq/tracer'

class RailsSidekiqTest < ActionController::TestCase
  setup do
    # don't pollute the global tracer
    @original_tracer = Datadog.configuration[:rails][:tracer]
    @tracer = get_test_tracer()
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

    def perform(); end
  end

  test 'Sidekiq middleware uses Rails configuration if available' do
    # configure Rails
    update_config(:enabled, false)
    update_config(:debug, true)
    update_config(:trace_agent_hostname, 'agent1.example.com')
    update_config(:trace_agent_port, '7777')
    db_adapter = get_adapter_name()

    # add Sidekiq middleware
    Sidekiq::Testing.server_middleware do |chain|
      chain.add(Datadog::Contrib::Sidekiq::Tracer, tracer: @tracer, service_name: 'rails-sidekiq')
    end

    # do something to force middleware execution
    EmptyWorker.perform_async()

    assert_equal(false, @tracer.enabled)
    assert_equal(
      @tracer.services,
      'rails-app' => {
        'app' => 'rack', 'app_type' => 'web'
      },
      'rails-controller' => {
        'app' => 'rails', 'app_type' => 'web'
      },
      db_adapter => {
        'app' => db_adapter, 'app_type' => 'db'
      },
      'rails-cache' => {
        'app' => 'rails', 'app_type' => 'cache'
      },
      'rails-sidekiq' => {
        'app' => 'sidekiq', 'app_type' => 'worker'
      }
    )
    assert_equal(true, Datadog::Tracer.debug_logging)
    assert_equal('agent1.example.com', @tracer.writer.transport.hostname)
    assert_equal('7777', @tracer.writer.transport.port)
  end
end
