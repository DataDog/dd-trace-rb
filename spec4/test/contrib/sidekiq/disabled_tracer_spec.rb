require('contrib/sidekiq/tracer_test_base')
class DisabledTracerTest < TracerTestBase
  class EmptyWorker
    include(Sidekiq::Worker)
    def perform
      # do nothing
    end
  end
  before do
    super
    Sidekiq::Testing.server_middleware do |chain|
      @tracer.configure(enabled: false)
      chain.add(Datadog::Contrib::Sidekiq::Tracer, tracer: @tracer)
    end
  end
  it('empty') do
    EmptyWorker.perform_async
    spans = @writer.spans
    expect(spans.length).to(eq(0))
  end
end
