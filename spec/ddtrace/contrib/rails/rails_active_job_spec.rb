# This module tests the right integration between Sidekiq and
# Rails. Functionality tests for Rails and Sidekiq must go
# in their testing modules.
require 'sidekiq/testing'
require 'ddtrace/contrib/sidekiq/server_tracer'
require 'active_job'

require 'ddtrace/contrib/rails/rails_helper'

RSpec.describe 'Rails application with Sidekiq' do
  include_context 'Rails test application'
  include_context 'Tracer'

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("USE_SIDEKIQ").and_return("true")
  end

  before do
    # don't pollute the global tracer
    @original_tracer = Datadog.configuration[:rails][:tracer]
    @original_writer = @original_tracer.writer

    Datadog.tracer.writer = tracer.writer

    Datadog.configuration[:rails][:tracer] = tracer

    # configure Sidekiq
    Sidekiq.configure_client do |config|
      config.redis = {url: ENV['REDIS_URL']}
    end

    Sidekiq.configure_server do |config|
      config.redis = {url: ENV['REDIS_URL']}
    end

    Sidekiq::Testing.inline!
  end

  after do
    Datadog.configuration[:rails][:tracer] = @original_tracer
    Datadog.configuration[:rails][:tracer].writer = @original_writer
  end

  before { app }

  context 'with a Sidekiq::Worker' do
    subject(:worker) do
      stub_const('EmptyWorker', Class.new do
        include Sidekiq::Worker

        def perform; end
      end)
    end

    it 'has correct Sidekiq span' do
      worker.perform_async

      expect(span.name).to eq('sidekiq.job')
      expect(span.resource).to eq('EmptyWorker')
      expect(span.get_tag('sidekiq.job.wrapper')).to be_nil
      expect(span.get_tag('sidekiq.job.id')).to match(/[0-9a-f]{24}/)
      expect(span.get_tag('sidekiq.job.retry')).to eq('true')
      expect(span.get_tag('sidekiq.job.queue')).to eq('default')
    end
  end

  context 'with an ActiveJob' do
    subject(:worker) do
      stub_const('EmptyJob', Class.new(ActiveJob::Base) do
        def perform; end
      end)
    end

    it 'has correct Sidekiq span' do
      worker.perform_later

      expect(span.name).to eq('sidekiq.job')
      expect(span.resource).to eq('EmptyJob')
      expect(span.get_tag('sidekiq.job.wrapper')).to eq('ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper')
      expect(span.get_tag('sidekiq.job.id')).to match(/[0-9a-f]{24}/)
      expect(span.get_tag('sidekiq.job.retry')).to eq('true')
      expect(span.get_tag('sidekiq.job.queue')).to eq('default')
    end
  end
end
