# This module tests the right integration between Sidekiq and
# Rails. Functionality tests for Rails and Sidekiq must go
# in their testing modules.

ENV['USE_SIDEKIQ'] = 'true'
RAILS_VERSION_FOR_ACTIVE_JOB = '4.2'.freeze

require 'helper'
require 'sidekiq/testing'
require 'contrib/rails/test_helper'
require 'ddtrace/contrib/sidekiq/tracer'

class RailsSidekiqTest < ActionController::TestCase
  setup do
    # don't pollute the global tracer
    @original_tracer = Rails.configuration.datadog_trace[:tracer]
    @tracer = get_test_tracer()
    Rails.configuration.datadog_trace[:tracer] = @tracer

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
    Rails.configuration.datadog_trace[:tracer] = @original_tracer
  end

  # Sidekiq test job
  class EmptyWorker
    include Sidekiq::Worker

    def perform(); end
  end

  if Rails::VERSION::STRING >= RAILS_VERSION_FOR_ACTIVE_JOB
    require 'active_job'

    # ActiveJob test job
    class EmptyJob < ActiveJob::Base
      def perform(); end
    end
  end

  test 'Sidekiq middleware uses Rails configuration if available' do
    # configure Rails
    update_config(:enabled, false)
    update_config(:sidekiq_service, 'rails-sidekiq')
    update_config(:debug, true)
    update_config(:trace_agent_hostname, 'agent1.example.com')
    update_config(:trace_agent_port, '7777')
    db_adapter = get_adapter_name()

    # add Sidekiq middleware
    Sidekiq::Testing.server_middleware do |chain|
      chain.add(Datadog::Contrib::Sidekiq::Tracer, tracer: @tracer)
    end

    # do something to force middleware execution
    EmptyWorker.perform_async()

    assert_equal(false, @tracer.enabled)
    assert_equal(
      @tracer.services,
      'rails-app' => {
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

  test 'Sidekiq middleware sends spans with the correct metadata' do
    # configure Rails
    update_config(:sidekiq_service, 'rails-sidekiq')

    # add Sidekiq middleware
    Sidekiq::Testing.server_middleware do |chain|
      chain.add(Datadog::Contrib::Sidekiq::Tracer, tracer: @tracer)
    end

    @tracer.writer.spans() # empty test queue

    # do something to force middleware execution
    EmptyWorker.perform_async()

    spans = []
    100.times do
      spans = @tracer.writer.spans()
      break unless spans.empty?
      sleep(0.1)
    end

    assert_equal(1, spans.length)
    span = spans[0]
    assert_equal('sidekiq.job', span.name)
    assert_equal('RailsSidekiqTest::EmptyWorker', span.resource)
    assert_nil(span.get_tag('sidekiq.job.wrapper'))
    assert_match(/([0-9]|[a-f]){24}/, span.get_tag('sidekiq.job.id'))
    assert_equal('true', span.get_tag('sidekiq.job.retry'))
    assert_equal('default', span.get_tag('sidekiq.job.queue'))
  end

  test 'Active job using Sidekiq sends spans with the correct metadata' do
    return if Rails::VERSION::STRING < RAILS_VERSION_FOR_ACTIVE_JOB

    # configure Rails
    update_config(:sidekiq_service, 'rails-sidekiq')

    # add Sidekiq middleware
    Sidekiq::Testing.server_middleware do |chain|
      chain.add(Datadog::Contrib::Sidekiq::Tracer, tracer: @tracer)
    end

    @tracer.writer.spans() # empty test queue

    # do something to force middleware execution
    EmptyJob.perform_now()

    spans = []
    100.times do
      spans = @tracer.writer.spans()
      break unless spans.empty?
      sleep(0.1)
    end

    assert_equal(1, spans.length)
    span = spans[0]
    assert_equal('sidekiq.job', span.name)
    assert_equal('RailsSidekiqTest::EmptyJob', span.resource)
    assert_equal('TODO', span.resource, span.get_tag('sidekiq.job.wrapper'))
    assert_match(/([0-9]|[a-f]){24}/, span.get_tag('sidekiq.job.id'))
    assert_equal('true', span.get_tag('sidekiq.job.retry'))
    assert_equal('default', span.get_tag('sidekiq.job.queue'))
  end
end
