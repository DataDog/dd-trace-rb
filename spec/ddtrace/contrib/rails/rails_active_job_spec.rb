# This module tests the right integration between Sidekiq and
# Rails. Functionality tests for Rails and Sidekiq must go
# in their testing modules.
require 'sidekiq/testing'
require 'ddtrace/contrib/sidekiq/server_tracer'
begin
  require 'active_job'
rescue LoadError
  puts 'ActiveJob not supported in this version of Rails'
end

require 'ddtrace/contrib/rails/rails_helper'

RSpec.describe 'Rails with Sidekiq' do
  before { skip unless defined? ::ActiveJob }

  include_context 'Rails test application'

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('USE_SIDEKIQ').and_return('true')
  end

  before do
    Datadog.configuration[:sidekiq][:tracer] = tracer

    Sidekiq.configure_client do |config|
      config.redis = { url: ENV['REDIS_URL'] }
    end

    Sidekiq.configure_server do |config|
      config.redis = { url: ENV['REDIS_URL'] }
    end

    Sidekiq::Testing.inline!
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
