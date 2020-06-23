
require 'contrib/sidekiq/tracer_test_base'

class DisabledTracerTest < TracerTestBase
  class EmptyWorker
    include Sidekiq::Worker

    def perform; end
  end

  def setup
    super

    Sidekiq::Testing.server_middleware do |chain|
      Datadog.tracer.configure(enabled: false)
      chain.add(Datadog::Contrib::Sidekiq::ServerTracer)
    end
  end

  def test_empty
    EmptyWorker.perform_async()

    assert_equal(0, spans.length)
  end
end
