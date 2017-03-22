# This module tests the right integration between Sidekiq and
# Rails. Functionality tests for Rails and Sidekiq must go
# in their testing modules.

ENV['USE_SIDEKIQ'] = 'true'

require 'helper'
require 'sidekiq/testing'
require 'contrib/rails/test_helper'
require 'ddtrace/contrib/sidekiq/tracer'
require 'active_job'

class RailsActiveJobTest < ActionController::TestCase
  setup do
    # don't pollute the global tracer
    @original_tracer = Rails.configuration.datadog_trace[:tracer]
    @original_writer = @original_tracer.writer

    @tracer = get_test_tracer()
    Datadog.tracer.writer = @tracer.writer

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
    Rails.configuration.datadog_trace[:tracer].writer = @original_writer
  end

  # Sidekiq test job
  class EmptyWorker
    include Sidekiq::Worker

    def perform
      puts 'doing an empty work'
    end
  end

  # ActiveJob test job
  class EmptyJob < ActiveJob::Base
    # Set the Queue as Default
    queue_as :default

    def perform
      puts 'doing an active job'
    end
  end

  test 'Sidekiq middleware sends spans with the correct metadata' do
    sleep(0.1)
    @tracer.writer.spans() # empty test queue

    # do something
    EmptyWorker.perform_async()

    spans = []
    50.times do
      spans = @tracer.writer.spans()
      break unless spans.empty?
      sleep 0.1
    end

    assert_equal(1, spans.length)
    span = spans[0]
    assert_equal('sidekiq.job', span.name)
    assert_equal('RailsActiveJobTest::EmptyWorker', span.resource,
                 'resource should be class doing the job')
    assert_nil(span.get_tag('sidekiq.job.wrapper'))
    assert_match(/([0-9]|[a-f]){24}/, span.get_tag('sidekiq.job.id'),
                 'Job ID should be a 96-bit integer')
    assert_equal('true', span.get_tag('sidekiq.job.retry'))
    assert_equal('default', span.get_tag('sidekiq.job.queue'))
  end

  test 'Active job using Sidekiq sends spans with the correct metadata' do
    sleep(0.1)
    @tracer.writer.spans() # empty test queue

    # do something
    EmptyJob.perform_later()

    spans = []
    50.times do
      spans = @tracer.writer.spans()
      break unless spans.empty?
      sleep 0.1
    end

    assert_equal(1, spans.length)
    span = spans[0]
    assert_equal('sidekiq.job', span.name)
    assert_equal('RailsActiveJobTest::EmptyJob', span.resource,
                 'resource should be the actual working class, doing the job')
    assert_equal('ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper', span.get_tag('sidekiq.job.wrapper'),
                 'wrapper should be the wrapping class, from Active Job')
    assert_match(/([0-9]|[a-f]){24}/, span.get_tag('sidekiq.job.id'),
                 'Job ID should be a 96-bit integer')
    assert_equal('true', span.get_tag('sidekiq.job.retry'))
    assert_equal('default', span.get_tag('sidekiq.job.queue'))
  end
end
