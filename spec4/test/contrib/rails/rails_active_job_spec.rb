ENV['USE_SIDEKIQ'] = 'true'
require('helper')
require('sidekiq/testing')
require('contrib/rails/test_helper')
require('ddtrace/contrib/sidekiq/tracer')
require('active_job')
RSpec.describe(RailsActiveJob) do
  before do
    @original_tracer = Datadog.configuration[:rails][:tracer]
    @original_writer = @original_tracer.writer
    @tracer = get_test_tracer
    Datadog.tracer.writer = @tracer.writer
    Datadog.configuration[:rails][:tracer] = @tracer
    Sidekiq.configure_client do |config|
      config.redis = { url: ENV['REDIS_URL'] }
    end
    Sidekiq.configure_server do |config|
      config.redis = { url: ENV['REDIS_URL'] }
    end
    Sidekiq::Testing.inline!
  end
  after do
    Datadog.configuration[:rails][:tracer] = @original_tracer
    Datadog.configuration[:rails][:tracer].writer = @original_writer
  end
  class EmptyWorker
    include(Sidekiq::Worker)
    def perform
      puts('doing an empty work')
    end
  end
  class EmptyJob < ActiveJob::Base
    queue_as(:default)
    # Set the Queue as Default
    def perform
      puts('doing an active job')
    end
  end
  it('Sidekiq middleware sends spans with the correct metadata') do
    sleep(0.1)
    @tracer.writer.spans
    EmptyWorker.perform_async
    spans = @tracer.writer.spans
    expect(spans.length).to(eq(1))
    span = spans[0]
    expect(span.name).to(eq('sidekiq.job'))
    expect(span.resource).to(eq('RailsActiveJobTest::EmptyWorker'))
    expect(span.get_tag('sidekiq.job.wrapper')).to(be_nil)
    expect(span.get_tag('sidekiq.job.id')).to(match(/[0-9a-f]{24}/))
    expect(span.get_tag('sidekiq.job.retry')).to(eq('true'))
    expect(span.get_tag('sidekiq.job.queue')).to(eq('default'))
  end
  it('Active job using Sidekiq sends spans with the correct metadata') do
    sleep(0.1)
    @tracer.writer.spans
    EmptyJob.perform_later
    spans = @tracer.writer.spans
    expect(spans.length).to(eq(1))
    span = spans[0]
    expect(span.name).to(eq('sidekiq.job'))
    expect(span.resource).to(eq('RailsActiveJobTest::EmptyJob'))
    expect(span.get_tag('sidekiq.job.wrapper')).to(eq('ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper'))
    expect(span.get_tag('sidekiq.job.id')).to(match(/[0-9a-f]{24}/))
    expect(span.get_tag('sidekiq.job.retry')).to(eq('true'))
    expect(span.get_tag('sidekiq.job.queue')).to(eq('default'))
  end
end
