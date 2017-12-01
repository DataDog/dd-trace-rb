require 'contrib/sidekiq/tracer_test_base'

class TracerTest < TracerTestBase
  class EmptyWorker
    include Sidekiq::Worker

    def perform(); end
  end

  def test_configuration_defaults
    # it should configure the tracer with reasonable defaults
    Sidekiq::Testing.server_middleware do |chain|
      chain.add(Datadog::Contrib::Sidekiq::Tracer, tracer: @tracer)
    end
    EmptyWorker.perform_async()

    assert_equal(true, @tracer.enabled)
    assert_equal(
      @writer.services,
      'sidekiq' => {
        'app' => 'sidekiq', 'app_type' => 'worker'
      }
    )
    assert_equal(false, Datadog::Tracer.debug_logging)
    assert_equal('localhost', @tracer.writer.transport.hostname)
    assert_equal('8126', @tracer.writer.transport.port)
  end

  def test_configuration_custom
    # it should configure the tracer with users' settings
    Sidekiq::Testing.server_middleware do |chain|
      chain.add(
        Datadog::Contrib::Sidekiq::Tracer,
        tracer: @tracer,
        enabled: false,
        service_name: 'my-sidekiq',
        debug: true,
        trace_agent_hostname: 'trace.example.com',
        trace_agent_port: '7777'
      )
    end
    EmptyWorker.perform_async()

    assert_equal(false, @tracer.enabled)
    assert_equal(
      @tracer.services,
      'my-sidekiq' => {
        'app' => 'sidekiq', 'app_type' => 'worker'
      }
    )
    assert_equal(true, Datadog::Tracer.debug_logging)
    assert_equal('trace.example.com', @tracer.writer.transport.hostname)
    assert_equal('7777', @tracer.writer.transport.port)
  end
end
