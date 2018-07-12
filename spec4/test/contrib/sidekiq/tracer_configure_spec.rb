require('contrib/sidekiq/tracer_test_base')
class TracerTest < TracerTestBase
  class EmptyWorker
    include(Sidekiq::Worker)
    def perform
      # do nothing
    end
  end
  it('configuration defaults') do
    Sidekiq::Testing.server_middleware do |chain|
      chain.add(Datadog::Contrib::Sidekiq::Tracer, tracer: @tracer)
    end
    EmptyWorker.perform_async
    expect('sidekiq' => { 'app' => 'sidekiq', 'app_type' => 'worker' }).to(eq(@writer.services))
  end
  it('configuration custom') do
    @tracer.configure(enabled: false)
    Sidekiq::Testing.server_middleware do |chain|
      chain.add(Datadog::Contrib::Sidekiq::Tracer, tracer: @tracer, service_name: 'my-sidekiq')
    end
    EmptyWorker.perform_async
    expect('my-sidekiq' => { 'app' => 'sidekiq', 'app_type' => 'worker' }).to(eq(@tracer.services))
  end
end
