require 'contrib/sidekiq/tracer_test_base'

class ClientTracerTest < TracerTestBase
  class EmptyWorker
    include Sidekiq::Worker

    def perform(); end
  end

  def setup
    super

    Sidekiq.configure_client do |config|
      config.client_middleware.clear

      config.client_middleware do |chain|
        chain.add(Datadog::Contrib::Sidekiq::ClientTracer,
                  tracer: @tracer, enabled: true)
      end
    end

    Sidekiq::Testing.server_middleware.clear
  end

  def test_empty
    @tracer.trace('parent.span', service: 'parent-service') do
      EmptyWorker.perform_async
    end

    spans = @writer.spans
    assert_equal(2, spans.length)

    parent_span = spans[0]
    assert_equal('parent.span', parent_span.name)
    assert_equal(0, parent_span.status)
    assert_nil(parent_span.parent)

    child_span = spans[1]
    assert_equal('sidekiq', child_span.service)
    assert_equal('ClientTracerTest::EmptyWorker', child_span.resource)
    assert_equal('default', child_span.get_tag('sidekiq.job.queue'))
    assert_equal(0, child_span.status)
    assert_equal(parent_span, child_span.parent)
  end

  def test_empty_parentless
    EmptyWorker.perform_async

    spans = @writer.spans
    assert_equal(1, spans.length)

    span = spans.first
    assert_equal('sidekiq', span.service)
    assert_equal('ClientTracerTest::EmptyWorker', span.resource)
    assert_equal('default', span.get_tag('sidekiq.job.queue'))
    assert_equal(0, span.status)
    assert_nil(span.parent)
  end
end
