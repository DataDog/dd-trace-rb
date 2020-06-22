require 'contrib/sidekiq/tracer_test_base'

class ClientTracerTest < TracerTestBase
  class EmptyWorker
    include Sidekiq::Worker

    def perform(); end
  end

  class DelayableClass
    def self.do_work; end
  end

  def setup
    super

    Sidekiq.configure_client do |config|
      config.client_middleware.clear

      config.client_middleware do |chain|
        chain.add(Datadog::Contrib::Sidekiq::ClientTracer, enabled: true)
      end
    end

    Sidekiq::Testing.server_middleware.clear
    Sidekiq::Extensions.enable_delay! if Sidekiq::VERSION > '5.0.0'
  end

  def test_empty
    tracer.trace('parent.span', service: 'parent-service') do
      EmptyWorker.perform_async
    end

    assert_equal(2, spans.length)

    parent_span, child_span = spans

    assert_equal('parent.span', parent_span.name)
    assert_equal(0, parent_span.status)
    assert_nil(parent_span.parent)

    assert_equal('sidekiq-client', child_span.service)
    assert_equal('ClientTracerTest::EmptyWorker', child_span.resource)
    assert_equal('default', child_span.get_tag('sidekiq.job.queue'))
    assert_equal(0, child_span.status)
    assert_equal(parent_span, child_span.parent)
    assert_nil(child_span.get_metric('_dd.measured'))
  end

  def test_empty_parentless
    EmptyWorker.perform_async

    assert_equal(1, spans.length)

    span = spans.first
    assert_equal('sidekiq-client', span.service)
    assert_equal('ClientTracerTest::EmptyWorker', span.resource)
    assert_equal('default', span.get_tag('sidekiq.job.queue'))
    assert_equal(0, span.status)
    assert_nil(span.parent)
    assert_nil(span.get_metric('_dd.measured'))
  end

  def test_delayed_extensions
    DelayableClass.delay.do_work
    assert_equal('ClientTracerTest::DelayableClass.do_work', spans.first.resource)
  end
end
