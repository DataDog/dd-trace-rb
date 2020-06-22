require 'contrib/sidekiq/tracer_test_base'

class TracerTest < TracerTestBase
  class EmptyWorker
    include Sidekiq::Worker

    def perform(); end
  end

  def test_configuration_defaults
    # it should configure the tracer with reasonable defaults
    Sidekiq::Testing.server_middleware do |chain|
      chain.add(Datadog::Contrib::Sidekiq::ServerTracer)
    end
    EmptyWorker.perform_async()
  end

  def test_configuration_custom
    # it should configure the tracer with users' settings
    Datadog.tracer.configure(enabled: false)
    Sidekiq::Testing.server_middleware do |chain|
      chain.add(
        Datadog::Contrib::Sidekiq::ServerTracer,
        service_name: 'my-sidekiq'
      )
    end
    EmptyWorker.perform_async()
  end
end
