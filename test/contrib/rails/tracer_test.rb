require 'helper'

require 'contrib/rails/test_helper'

class TracerTest < ActionController::TestCase
  setup do
    # don't pollute the global tracer
    @tracer = get_test_tracer
    Rails.configuration.datadog_trace[:tracer] = @tracer
  end

  teardown do
    reset_config()
  end

  test 'the configuration is correctly called' do
    assert Rails.configuration.datadog_trace[:enabled]
    assert Rails.configuration.datadog_trace[:auto_instrument]
    assert_equal(Rails.configuration.datadog_trace[:default_service], 'rails-app')
    assert_equal(Rails.configuration.datadog_trace[:template_base_path], 'views/')
    assert Rails.configuration.datadog_trace[:tracer]
    assert !Rails.configuration.datadog_trace[:debug]
    assert_equal(Rails.configuration.datadog_trace[:trace_agent_hostname], Datadog::Writer::HOSTNAME)
    assert_equal(Rails.configuration.datadog_trace[:trace_agent_port], Datadog::Writer::PORT)
    assert_equal(Rails.configuration.datadog_trace[:env], 'test')
    assert_equal(Rails.configuration.datadog_trace[:tags], {})
  end

  test 'a default service and database should be properly set' do
    tracer = Datadog.tracer
    adapter_name = get_adapter_name()
    assert_equal(
      tracer.services,
      'rails-app' => {
        'app' => 'rails', 'app_type' => 'web'
      },
      adapter_name => {
        'app' => adapter_name, 'app_type' => 'db'
      },
      'rails-cache' => {
        'app' => 'rails', 'app_type' => 'cache'
      }
    )
  end

  test 'database service can be changed by user' do
    update_config(:default_database_service, 'customer-db')
    tracer = Rails.configuration.datadog_trace[:tracer]
    adapter_name = get_adapter_name()

    assert_equal(
      tracer.services,
      'rails-app' => {
        'app' => 'rails', 'app_type' => 'web'
      },
      'customer-db' => {
        'app' => adapter_name, 'app_type' => 'db'
      },
      'rails-cache' => {
        'app' => 'rails', 'app_type' => 'cache'
      }
    )
  end

  test 'application service can be changed by user' do
    update_config(:default_service, 'my-custom-app')
    tracer = Rails.configuration.datadog_trace[:tracer]
    adapter_name = get_adapter_name()

    assert_equal(
      tracer.services,
      'my-custom-app' => {
        'app' => 'rails', 'app_type' => 'web'
      },
      adapter_name => {
        'app' => adapter_name, 'app_type' => 'db'
      },
      'rails-cache' => {
        'app' => 'rails', 'app_type' => 'cache'
      }
    )
  end

  test 'cache service can be changed by user' do
    update_config(:default_cache_service, 'service-cache')
    tracer = Rails.configuration.datadog_trace[:tracer]
    adapter_name = get_adapter_name()

    assert_equal(
      tracer.services,
      'rails-app' => {
        'app' => 'rails', 'app_type' => 'web'
      },
      adapter_name => {
        'app' => adapter_name, 'app_type' => 'db'
      },
      'service-cache' => {
        'app' => 'rails', 'app_type' => 'cache'
      }
    )
  end

  test 'debug logging can be changed by the user' do
    update_config(:debug, true)

    assert_equal(Datadog::Tracer.debug_logging, true)
  end

  test 'tracer agent address can be changed by the user' do
    update_config(:trace_agent_hostname, 'example.com')
    update_config(:trace_agent_port, 42)

    tracer = Rails.configuration.datadog_trace[:tracer]

    assert_equal(tracer.writer.transport.hostname, 'example.com')
    assert_equal(tracer.writer.transport.port, 42)
  end

  test 'tracer environment can be changed by the user' do
    update_config(:env, 'dev')

    tracer = Rails.configuration.datadog_trace[:tracer]

    assert_equal(tracer.tags['env'], 'dev')
  end

  test 'tracer global tags can be changed by the user' do
    update_config(:tags, 'component' => 'api', 'section' => 'users')

    tracer = Rails.configuration.datadog_trace[:tracer]

    assert_equal(tracer.tags['component'], 'api')
    assert_equal(tracer.tags['section'], 'users')
  end

  test 'tracer env setting has precedence over tags setting' do
    # default case
    update_config(:tags, 'env' => 'foo')
    tracer = Rails.configuration.datadog_trace[:tracer]
    assert_equal(tracer.tags['env'], 'test')

    # explicit set
    update_config(:env, 'dev')
    update_config(:tags, 'env' => 'bar')
    tracer = Rails.configuration.datadog_trace[:tracer]
    assert_equal(tracer.tags['env'], 'dev')
  end
end
