require 'contrib/sidekiq/tracer_test_base'

class ServerTracerTest < TracerTestBase
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
      { service_name: 'sidekiq-slow', tag_args: true }
    end

    def perform(args); end
  end

  class DelayableClass
    def self.do_work; end
  end

  def setup
    super

    Sidekiq::Testing.server_middleware do |chain|
      chain.add(Datadog::Contrib::Sidekiq::ServerTracer, enabled: true)
    end
    Sidekiq::Extensions.enable_delay! if Sidekiq::VERSION > '5.0.0'
  end

  def test_empty
    EmptyWorker.perform_async()

    assert_equal(2, spans.length)

    span, _push = spans
    assert_equal('sidekiq', span.service)
    assert_equal('ServerTracerTest::EmptyWorker', span.resource)
    assert_equal('default', span.get_tag('sidekiq.job.queue'))
    refute_nil(span.get_tag('sidekiq.job.delay'))
    assert_equal(0, span.status)
    assert_nil(span.parent)
    assert_nil(span.get_tag('sidekiq.job.args'))
    assert_equal(span.get_metric('_dd.measured'), 1.0)
  end

  # rubocop:disable Lint/HandleExceptions
  def test_error
    begin
      ErrorWorker.perform_async()
    rescue TestError
    end

    assert_equal(2, spans.length)

    span, _push = spans
    assert_equal('sidekiq', span.service)
    assert_equal('ServerTracerTest::ErrorWorker', span.resource)
    assert_equal('default', span.get_tag('sidekiq.job.queue'))
    refute_nil(span.get_tag('sidekiq.job.delay'))
    assert_equal(1, span.status)
    assert_equal('job error', span.get_tag(Datadog::Ext::Errors::MSG))
    assert_equal('ServerTracerTest::TestError', span.get_tag(Datadog::Ext::Errors::TYPE))
    assert_nil(span.parent)
    assert_nil(span.get_tag('sidekiq.job.args'))
    assert_equal(span.get_metric('_dd.measured'), 1.0)
  end

  def test_custom
    EmptyWorker.perform_async()
    CustomWorker.perform_async('random_id')

    assert_equal(4, spans.length)

    custom, empty, _push, _push = spans

    assert_equal('sidekiq', empty.service)
    assert_equal('ServerTracerTest::EmptyWorker', empty.resource)
    assert_equal('default', empty.get_tag('sidekiq.job.queue'))
    refute_nil(empty.get_tag('sidekiq.job.delay'))
    assert_equal(0, empty.status)
    assert_nil(empty.parent)
    assert_equal(empty.get_metric('_dd.measured'), 1.0)

    assert_equal('sidekiq-slow', custom.service)
    assert_equal('ServerTracerTest::CustomWorker', custom.resource)
    assert_equal('default', custom.get_tag('sidekiq.job.queue'))
    assert_equal(0, custom.status)
    assert_nil(custom.parent)
    assert_equal(['random_id'].to_s, custom.get_tag('sidekiq.job.args'))
    assert_equal(custom.get_metric('_dd.measured'), 1.0)
  end

  def test_delayed_extensions
    DelayableClass.delay.do_work
    assert_equal('ServerTracerTest::DelayableClass.do_work', spans.first.resource)
  end
end
