
require 'contrib/sidekiq/tracer_test_base'

class TracerTest < TracerTestBase
  class TestError < StandardError; end

  class EmptyWorker
    include Sidekiq::Worker

    def perform(); end
  end

  class ErrorWorker
    include Sidekiq::Worker

    def perform
      raise TestError, 'job error'
    end
  end

  class CustomWorker
    include Sidekiq::Worker

    def self.datadog_tracer_config
      { service_name: 'sidekiq-slow' }
    end

    def perform(); end
  end

  def setup
    super

    Sidekiq::Testing.server_middleware do |chain|
      chain.add(Datadog::Contrib::Sidekiq::Tracer,
                tracer: @tracer, enabled: true)
    end
  end

  def test_empty
    EmptyWorker.perform_async()

    spans = @writer.spans()
    assert_equal(1, spans.length)

    services = @writer.services()
    assert_equal(1, services.length)

    span = spans[0]
    assert_equal('sidekiq', span.service)
    assert_equal('TracerTest::EmptyWorker', span.resource)
    assert_equal('default', span.get_tag('sidekiq.job.queue'))
    assert_equal(0, span.status)
    assert_nil(span.parent)
  end

  # rubocop:disable Lint/HandleExceptions
  def test_error
    begin
      ErrorWorker.perform_async()
    rescue TestError
    end

    spans = @writer.spans()
    assert_equal(1, spans.length)

    services = @writer.services()
    assert_equal(1, services.length)

    span = spans[0]
    assert_equal('sidekiq', span.service)
    assert_equal('TracerTest::ErrorWorker', span.resource)
    assert_equal('default', span.get_tag('sidekiq.job.queue'))
    assert_equal(1, span.status)
    assert_equal('job error', span.get_tag(Datadog::Ext::Errors::MSG))
    assert_equal('TracerTest::TestError', span.get_tag(Datadog::Ext::Errors::TYPE))
    assert_nil(span.parent)
  end

  def test_custom
    EmptyWorker.perform_async()
    CustomWorker.perform_async()

    spans = @writer.spans()
    assert_equal(2, spans.length)

    services = @writer.services()
    assert_equal(2, services.length)

    custom, empty = spans

    assert_equal('sidekiq', empty.service)
    assert_equal('TracerTest::EmptyWorker', empty.resource)
    assert_equal('default', empty.get_tag('sidekiq.job.queue'))
    assert_equal(0, empty.status)
    assert_nil(empty.parent)

    assert_equal('sidekiq-slow', custom.service)
    assert_equal('TracerTest::CustomWorker', custom.resource)
    assert_equal('default', custom.get_tag('sidekiq.job.queue'))
    assert_equal(0, custom.status)
    assert_nil(custom.parent)
  end
end
