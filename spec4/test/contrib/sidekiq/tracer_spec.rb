require('contrib/sidekiq/tracer_test_base')
class TracerTest < TracerTestBase
  class TestError < StandardError
  end
  class EmptyWorker
    include(Sidekiq::Worker)
    def perform
      # do nothing
    end
  end
  class ErrorWorker
    include(Sidekiq::Worker)
    def perform
      raise(TestError, 'job error')
    end
  end
  class CustomWorker
    include(Sidekiq::Worker)
    def self.datadog_tracer_config
      { service_name: 'sidekiq-slow' }
    end

    def perform
      # do nothing
    end
  end
  before do
    super
    Sidekiq::Testing.server_middleware do |chain|
      chain.add(Datadog::Contrib::Sidekiq::Tracer, tracer: @tracer, enabled: true)
    end
  end
  it('empty') do
    EmptyWorker.perform_async
    spans = @writer.spans
    expect(spans.length).to(eq(1))
    services = @writer.services
    expect(services.length).to(eq(1))
    span = spans[0]
    expect(span.service).to(eq('sidekiq'))
    expect(span.resource).to(eq('TracerTest::EmptyWorker'))
    expect(span.get_tag('sidekiq.job.queue')).to(eq('default'))
    refute_nil(span.get_tag('sidekiq.job.delay'))
    expect(span.status).to(eq(0))
    expect(span.parent).to(be_nil)
  end
  it('error') do
    begin
      ErrorWorker.perform_async
      # rubocop:disable Lint/HandleExceptions
    rescue TestError
      # rubocop:enable Lint/HandleExceptions
      # do nothing
    end
    spans = @writer.spans
    expect(spans.length).to(eq(1))
    services = @writer.services
    expect(services.length).to(eq(1))
    span = spans[0]
    expect(span.service).to(eq('sidekiq'))
    expect(span.resource).to(eq('TracerTest::ErrorWorker'))
    expect(span.get_tag('sidekiq.job.queue')).to(eq('default'))
    refute_nil(span.get_tag('sidekiq.job.delay'))
    expect(span.status).to(eq(1))
    expect(span.get_tag(Datadog::Ext::Errors::MSG)).to(eq('job error'))
    expect(span.get_tag(Datadog::Ext::Errors::TYPE)).to(eq('TracerTest::TestError'))
    expect(span.parent).to(be_nil)
  end
  it('custom') do
    EmptyWorker.perform_async
    CustomWorker.perform_async
    spans = @writer.spans
    expect(spans.length).to(eq(2))
    services = @writer.services
    expect(services.length).to(eq(2))
    custom, empty = spans
    expect(empty.service).to(eq('sidekiq'))
    expect(empty.resource).to(eq('TracerTest::EmptyWorker'))
    expect(empty.get_tag('sidekiq.job.queue')).to(eq('default'))
    refute_nil(empty.get_tag('sidekiq.job.delay'))
    expect(empty.status).to(eq(0))
    expect(empty.parent).to(be_nil)
    expect(custom.service).to(eq('sidekiq-slow'))
    expect(custom.resource).to(eq('TracerTest::CustomWorker'))
    expect(custom.get_tag('sidekiq.job.queue')).to(eq('default'))
    expect(custom.status).to(eq(0))
    expect(custom.parent).to(be_nil)
  end
end
